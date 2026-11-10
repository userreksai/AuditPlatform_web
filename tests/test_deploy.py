"""Regression checks for standalone same-origin frontend deployment (no Nginx/root needed)."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch


RENDERER_PATH = Path(__file__).resolve().parents[1] / "deploy" / "render_nginx.py"
SPEC = importlib.util.spec_from_file_location("audit_web_render_nginx", RENDERER_PATH)
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)


class DeploymentConfigTests(unittest.TestCase):
    root = "/opt/aws-audit-web/current"

    def render(self, port=9100, backend="http://127.0.0.1:10001", ca_bundle="", release_id="initial"):
        return renderer.render_config(port, backend, self.root, ca_bundle, release_id)

    def test_cli_defaults_serve_9100_and_proxy_to_10001(self):
        result = subprocess.run(
            [sys.executable, str(RENDERER_PATH)], check=True,
            capture_output=True, text=True,
        )
        self.assertIn("listen 9100;", result.stdout)
        self.assertIn("proxy_pass http://127.0.0.1:10001;", result.stdout)
        self.assertIn(f"root {self.root};", result.stdout)

    def test_api_prefix_and_public_port_reach_go_unchanged(self):
        config = self.render()
        self.assertIn("location ^~ /api/", config)
        # A trailing slash here would strip /api/ from the upstream request URI.
        self.assertIn("proxy_pass http://127.0.0.1:10001;", config)
        self.assertNotIn("proxy_pass http://127.0.0.1:10001/;", config)
        # $host drops the public :9100 port and fails the Go Origin check.
        self.assertIn("proxy_set_header Host $http_host;", config)
        self.assertIn("proxy_set_header X-Forwarded-Proto $scheme;", config)

    def test_spa_fallback_keeps_missing_assets_out_of_index_html(self):
        config = self.render()
        self.assertIn("try_files $uri $uri/ /index.html;", config)
        self.assertIn("location /assets/", config)
        self.assertIn("try_files $uri =404;", config)
        self.assertIn("location = /api { return 404; }", config)

    def test_ipv6_backend_is_bracketed(self):
        for backend in ("http://[::1]:10001", "http://[2001:db8::1]:10001"):
            with self.subTest(backend=backend):
                self.assertIn(f"proxy_pass {backend};", self.render(backend=backend))

    def test_invalid_or_injected_origins_are_rejected(self):
        invalid = (
            "", "//example.com:10001", "ftp://example.com:10001",
            "http://user:password@example.com:10001",
            "http://127.0.0.1:10001/api", "http://127.0.0.1:10001/api/",
            "http://127.0.0.1:10001?token=value", "http://127.0.0.1:10001?",
            "http://127.0.0.1:10001#fragment", "http://127.0.0.1:10001#",
            "http://127.0.0.1:10001\n", "http://exam\nple.com:10001",
            "http://example.com;", "http://$backend:10001", 'http://example.com"',
            "http://example.com:abc", "http://example.com:", "http://example.com:0",
            "http://example.com:65536", "http://[::1]unexpected:10001",
        )
        for backend in invalid:
            with self.subTest(backend=backend), self.assertRaises(ValueError):
                self.render(backend=backend)

    def test_port_boundaries_are_accepted(self):
        for port in (1, 65535):
            with self.subTest(port=port):
                self.assertIn(f"listen {port};", self.render(port=port))

    def test_invalid_frontend_ports_are_rejected(self):
        for port in (0, -1, 65536, True, "9100", 9100.0, None):
            with self.subTest(port=port), self.assertRaises(ValueError):
                self.render(port=port)

    def test_local_same_port_proxy_loops_are_rejected(self):
        for host in ("localhost", "127.0.0.1", "127.0.0.2", "0.0.0.0", "[::1]", "[::]", "[::ffff:7f00:1]"):
            with self.subTest(host=host), self.assertRaises(ValueError):
                self.render(backend=f"http://{host}:9100")
        with self.assertRaises(ValueError):
            self.render(port=80, backend="http://localhost")

    def test_remote_backend_can_share_public_port(self):
        self.assertIn("proxy_pass http://192.0.2.10:9100;", self.render(backend="http://192.0.2.10:9100"))

    def test_https_enables_sni_and_certificate_verification(self):
        ca = "/etc/ssl/certs/mock-ca.pem"
        # POSIX system CA paths keep the test portable to Windows development hosts.
        with patch.object(renderer.Path, "is_file", return_value=True) as is_file:
            config = self.render(backend="https://api.example.com:10001", ca_bundle=ca)
        is_file.assert_called_once()
        self.assertIn("proxy_ssl_server_name on;", config)
        self.assertIn("proxy_ssl_verify on;", config)
        self.assertIn(f"proxy_ssl_trusted_certificate {ca};", config)

    def test_https_requires_existing_ca_bundle(self):
        with self.assertRaises(ValueError):
            self.render(backend="https://api.example.com:10001")
        with patch.object(renderer.Path, "is_file", return_value=False), self.assertRaises(ValueError):
            self.render(backend="https://api.example.com:10001", ca_bundle="/missing/ca.pem")

    def test_deployment_paths_cannot_inject_nginx_directives(self):
        for root in ("relative", "/opt/audit root", "/opt/audit;include/etc/passwd", "/opt/audit\nroot/etc"):
            with self.subTest(root=root), self.assertRaises(ValueError):
                renderer.render_config(9100, "http://127.0.0.1:10001", root)
        with patch.object(renderer.Path, "is_file", return_value=True), self.assertRaises(ValueError):
            self.render(backend="https://api.example.com:10001", ca_bundle="/ca.pem;ssl_verify_off")

    def test_health_endpoint_identifies_exact_release(self):
        release_id = "20261110T235959Z-123"
        config = self.render(release_id=release_id)
        self.assertIn("location = /__aws_audit_web_health", config)
        self.assertIn(f'return 200 "aws-audit-web:{release_id}\\n";', config)

    def test_release_identifier_cannot_inject_nginx_syntax(self):
        for release_id in ("", "unsafe/id", 'x";return 500;', "x\ny", "$hostname"):
            with self.subTest(release_id=release_id), self.assertRaises(ValueError):
                self.render(release_id=release_id)


if __name__ == "__main__":
    unittest.main()
