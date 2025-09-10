import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static values = { themes: Array }

  connect() {
    this.themes = this.themesValue?.length ? this.themesValue : ["light", "dark"]
    this.root = document.documentElement
    const saved = window.localStorage.getItem("theme")
    if (saved && this.themes.includes(saved)) {
      this.apply(saved)
    } else {
      this.apply(this.themes[0])
    }
  }

  toggle() {
    const current = this.root.getAttribute("data-theme")
    const idx = this.themes.indexOf(current)
    const next = this.themes[(idx + 1) % this.themes.length]
    this.apply(next)
  }

  apply(theme) {
    this.root.setAttribute("data-theme", theme)
    window.localStorage.setItem("theme", theme)
  }
}
