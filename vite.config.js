import { defineConfig } from 'vite';
import glsl from 'vite-plugin-glsl';

export default defineConfig({
  plugins: [glsl({ minify: true })],
  base: './',
  build: {
    minify: 'terser',
    terserOptions: {
      compress: { passes: 3 }
    },
    rollupOptions: {
      treeshake: { preset: 'smallest' }
    }
  }
});
