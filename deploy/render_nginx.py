"""Render the standalone frontend's same-origin Nginx configuration."""
import argparse
import ipaddress
from pathlib import Path
import re
from urllib.parse import urlsplit


def normalize_backend(value):
    if not value or any(char.isspace() for char in value):
        raise ValueError("backend must be an http(s) origin without whitespace")
    parsed = urlsplit(value)
    if (parsed.scheme not in ("http", "https") or not parsed.hostname
            or parsed.username is not None or parsed.password is not None
            or parsed.path not in ("", "/") or parsed.query or parsed.fragment
            or "?" in value or "#" in value):
        raise ValueError("backend must contain only scheme, hostname and optional port")
    if not re.fullmatch(r"(?:\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.-]+)(?::[0-9]+)?", parsed.netloc):
        raise ValueError("invalid backend host or port")
    host = parsed.hostname
    try:
        address = ipaddress.ip_address(host)
        host_literal = f"[{host}]" if address.version == 6 else host
    except ValueError:
        if not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", host):
            raise ValueError("invalid backend hostname") from None
        host_literal = host
    try:
        port = parsed.port
    except ValueError:
        raise ValueError("invalid backend port") from None
    if port is not None and not 1 <= port <= 65535:
        raise ValueError("backend port must be 1..65535")
    # Reconstruct instead of interpolating an untrusted netloc into Nginx syntax.
    return f"{parsed.scheme}://{host_literal}" + (f":{port}" if port is not None else "")


def safe_path(value):
    if not re.fullmatch(r"/[A-Za-z0-9_./-]+", str(value)):
        raise ValueError("deployment paths must be absolute and contain no whitespace or Nginx syntax")
    return str(value)


def render_config(port, backend, root, ca_bundle="", release_id="initial"):
    if isinstance(port, bool) or not isinstance(port, int) or not 1 <= port <= 65535:
        raise ValueError("frontend port must be 1..65535")
    backend = normalize_backend(backend)
    parsed = urlsplit(backend)
    backend_port = parsed.port or (443 if parsed.scheme == "https" else 80)
    local_host = parsed.hostname == "localhost"
    try:
        address = ipaddress.ip_address(parsed.hostname)
        local_host = local_host or address.is_loopback or address.is_unspecified
        mapped = getattr(address, "ipv4_mapped", None)
        if mapped is not None:
            local_host = local_host or mapped.is_loopback or mapped.is_unspecified
    except ValueError:
        pass
    if local_host and backend_port == port:
        raise ValueError("frontend and local backend cannot use the same port")
    root = safe_path(root)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", release_id):
        raise ValueError("invalid release identifier")
    tls = ""
    if parsed.scheme == "https":
        if not ca_bundle or not Path(ca_bundle).is_file():
            raise ValueError("HTTPS backend requires an existing system CA bundle")
        tls = ("        proxy_ssl_server_name on;\n"
               "        proxy_ssl_verify on;\n"
               f"        proxy_ssl_trusted_certificate {safe_path(ca_bundle)};\n")
    return f"""# Managed by AuditPlatform_web/install.sh. Browser entry: http://HOST:{port}
server {{
    listen {port};
    server_name _;
    root {root};
    index index.html;
    client_max_body_size 1m;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;

    location = /__aws_audit_web_health {{
        default_type text/plain;
        return 200 "aws-audit-web:{release_id}\\n";
    }}
    location = /api {{ return 404; }}
    location ^~ /api/ {{
        proxy_pass {backend};
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Connection "";
        proxy_connect_timeout 10s;
        proxy_read_timeout 60s;
{tls}    }}
    location /assets/ {{
        try_files $uri =404;
        expires 7d;
    }}
    location = /index.html {{
        expires -1;
    }}
    location / {{
        try_files $uri $uri/ /index.html;
    }}
}}
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=9100)
    parser.add_argument("--backend", default="http://127.0.0.1:10001")
    parser.add_argument("--root", default="/opt/aws-audit-web/current")
    parser.add_argument("--ca-bundle", default="")
    parser.add_argument("--release-id", default="initial")
    parser.add_argument("--output")
    parser.add_argument("--check", action="store_true", help="validate settings only")
    args = parser.parse_args()
    try:
        content = render_config(args.port, args.backend, args.root, args.ca_bundle, args.release_id)
    except ValueError as error:
        parser.error(str(error))
    if args.check:
        return
    if args.output:
        Path(args.output).write_text(content, encoding="utf-8")
    else:
        print(content, end="")


if __name__ == "__main__":
    main()
