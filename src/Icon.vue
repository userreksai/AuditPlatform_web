<script setup lang="ts">
withDefaults(defineProps<{ name: string; size?: number }>(), { size: 20 })
const paths: Record<string, string> = {
  shield: 'M12 3 20 6v6c0 5-8 9-8 9s-8-4-8-9V6z M8 12l3 3 5-6',
  grid: 'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
  users: 'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2 M16 4a4 4 0 0 1 0 8 M22 21v-2a4 4 0 0 0-3-3.87 M13 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0',
  building: 'M4 21V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v16 M2 21h20 M8 7h1 M15 7h1 M8 11h1 M15 11h1 M9 21v-6h6v6',
  clock: 'M12 8v5l3 2 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
  refresh: 'M20 7v5h-5 M4 17v-5h5 M6.1 6.1A8 8 0 0 1 20 12 M4 12a8 8 0 0 0 13.9 5.9',
  search: 'm21 21-5-5 M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0',
  chevron: 'm9 5 7 7-7 7',
  down: 'm6 9 6 6 6-6',
  logout: 'M9 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h4 M16 17l5-5-5-5 M21 12H9',
  key: 'm15 7 2 2 4-4 M21 3l-9 9 M13 16a5 5 0 1 1-10 0 5 5 0 0 1 10 0',
  alert: 'm12 3 10 18H2z M12 9v4 M12 17h.01',
  check: 'm5 12 4 4L19 6',
  close: 'm6 6 12 12 M6 18 18 6',
  download: 'M12 3v12 m-5-5 5 5 5-5 M4 16v5h16v-5',
  columns: 'M3 4h18v16H3z M9 4v16 M15 4v16',
  filter: 'M3 5h18 M6 12h12 M10 19h4',
  help: 'M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3 M12 17h.01 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
  lock: 'M5 10h14v11H5z M8 10V7a4 4 0 0 1 8 0v3 M12 14v3',
  cloud: 'M6 18a5 5 0 0 1-.9-9.9A7 7 0 0 1 18 7a5.5 5.5 0 0 1 .5 11z',
  copy: 'M9 9h12v12H9z M15 9V3H3v12h6',
  external: 'M15 3h6v6 M10 14 21 3 M21 14v7H3V3h7',
  file: 'M14 2H4v20h16V8z M14 2v6h6 M8 12h8 M8 16h6',
  menu: 'M3 6h18 M3 12h18 M3 18h18',
}
</script>
<template><svg :width="size" :height="size" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path :d="paths[name] || paths.shield" /></svg></template>
