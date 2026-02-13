import type { Config } from "tailwindcss";
import daisyui from "daisyui";

export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        display: ["Space Grotesk", "sans-serif"],
        body: ["IBM Plex Sans", "sans-serif"],
        mono: ["IBM Plex Mono", "monospace"],
      },
      colors: {
        ink: {
          DEFAULT: "#1a1a1a",
          muted: "#4b4b4b",
          subtle: "#7a6f5e",
        },
        sand: {
          50: "#fffdf7",
          100: "#f6f1e3",
          200: "#eadfc6",
          300: "#dacaa8",
          400: "#c5ae7f",
        },
        ember: {
          400: "#f47233",
          500: "#e4572e",
          600: "#c53e1a",
        },
        tide: {
          400: "#1f9a8a",
          500: "#137c70",
          600: "#0b5f56",
        },
        sky: {
          200: "#d7e6f5",
          300: "#b5cde8",
        },
      },
      boxShadow: {
        card: "0 18px 40px rgba(20, 15, 10, 0.12)",
        panel: "0 12px 26px rgba(20, 15, 10, 0.08)",
      },
      backgroundImage: {
        "grain": "radial-gradient(circle at 1px 1px, rgba(30, 30, 30, 0.05) 1px, transparent 0)",
      },
    },
  },
  plugins: [daisyui],
  daisyui: {
    themes: [
      {
        symbiotic: {
          primary: "#e4572e",
          secondary: "#137c70",
          accent: "#1f9a8a",
          neutral: "#1f2937",
          "base-100": "#fffdf7",
          "base-200": "#f6f1e3",
          "base-300": "#eadfc6",
          info: "#2563eb",
          success: "#0f766e",
          warning: "#f59e0b",
          error: "#b91c1c",
        },
      },
    ],
    base: false,
    logs: false,
  },
} satisfies Config;
