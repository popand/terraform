/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        'primary': '#00d4ff',
        'secondary': '#7c3aed',
        'dark': {
          100: '#1a1a2e',
          200: '#16213e',
          300: '#0d1117',
          400: '#0a0a0a'
        }
      }
    },
  },
  plugins: [],
}
