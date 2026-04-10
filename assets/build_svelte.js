const path = require("path");
const esbuild = require("esbuild");
const sveltePlugin = require("esbuild-svelte");

const isWatch = process.argv.includes("--watch");
const isMinify = process.argv.includes("--minify");

const buildOptions = {
  absWorkingDir: path.resolve(__dirname),
  entryPoints: ["svelte/index.js"],
  bundle: true,
  outdir: "../priv/static/assets/js/svelte",
  format: "esm",
  splitting: true,
  target: "es2022",
  minify: isMinify,
  sourcemap: isWatch ? "inline" : false,
  plugins: [
    sveltePlugin({
      compilerOptions: {
        css: "injected",
        compatibility: { componentApi: 4 },
      },
    }),
  ],
  logLevel: "info",
};

async function run() {
  if (isWatch) {
    const ctx = await esbuild.context(buildOptions);
    await ctx.watch();
    process.stdin.on("end", () => {
      ctx.dispose();
      process.exit(0);
    });
    process.stdin.resume();
  } else {
    await esbuild.build(buildOptions);
  }
}

run().catch((err) => {
  console.error(err);
  process.exit(1);
});
