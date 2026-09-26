/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        blue: {
          DEFAULT: '#7EC8E3',
          light: '#D6EEF9',
          deep: '#3E8FBF',
        },
        ink: {
          DEFAULT: '#1F2937',
          soft: '#5B6B7A',
        },
      },
      fontFamily: {
        sans: ['Inter', 'Cairo', 'sans-serif'],
      },
    },
  },
  plugins: [],
}
