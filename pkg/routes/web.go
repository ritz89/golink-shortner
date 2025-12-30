package routes

import (
	"boilerplate/app/controllers"
	"strings"

	"github.com/gofiber/fiber/v3"
)

// reservedPaths adalah daftar path yang tidak boleh ditangani oleh short link redirect
var reservedPaths = []string{
	"api",
	"admin",
	"dashboard",
	"health",
	"swagger",
	"static",
	"shorten",
}

// isReservedCode mengecek apakah code adalah reserved path
func isReservedCode(code string) bool {
	codeLower := strings.ToLower(code)
	for _, reserved := range reservedPaths {
		if codeLower == reserved {
			return true
		}
	}
	return false
}

// SetupWeb registers web routes
func SetupWeb(app *fiber.App) {
	// Index page (homepage)
	app.Get("/", controllers.IndexPage)

	// Public shorten endpoint (web UI)
	app.Post("/shorten", controllers.ShortenURL)

	// Short link redirect dengan pengecekan reserved paths
	app.Get("/:code", func(c fiber.Ctx) error {
		code := c.Params("code")

		// Skip jika code adalah reserved path
		if isReservedCode(code) {
			// Return 404 atau pass to next handler
			return c.Status(404).SendString("Not Found")
		}

		// Handle short link redirect
		return controllers.Redirect(c)
	})
}
