const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function({matchComponents, theme}) {
  let iconsDir = path.join(__dirname, "fontawesome")
  let values = {}
  let icons = [
    ["-regular", "/regular"],
    ["-solid", "/solid"],
    ["-brands", "/brands"]
  ]

  icons.forEach(([suffix, dir]) => {
    let fullPath = path.join(iconsDir, dir)

    // Check if directory exists before trying to read it
    if (fs.existsSync(fullPath)) {
      fs.readdirSync(fullPath).forEach(file => {
        let name = path.basename(file, ".svg") + suffix
        values[name] = {name, fullPath: path.join(fullPath, file)}
      })
    }
  })

  matchComponents({
    "fa": ({name, fullPath}) => {
      let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
      content = encodeURIComponent(content)
      let size = theme("spacing.6")

      // Use smaller size for regular icons if desired
      if (name.endsWith("-regular")) {
        size = theme("spacing.5")
      }

      return {
        [`--fa-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
        "-webkit-mask": `var(--fa-${name})`,
        "mask": `var(--fa-${name})`,
        "mask-repeat": "no-repeat",
        "background-color": "currentColor",
        "vertical-align": "middle",
        "display": "inline-block",
        "width": size,
        "height": size
      }
    }
  }, {values})
})
