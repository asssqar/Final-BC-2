import type {Config} from "tailwindcss";

const config: Config = {
    content: ["./src/**/*.{ts,tsx}"],
    theme: {
        extend: {
            colors: {
                aether: {
                    50: "#f5f9ff",
                    500: "#5b8bff",
                    700: "#3461d8",
                    900: "#1f2952",
                },
            },
        },
    },
    plugins: [],
};
export default config;
