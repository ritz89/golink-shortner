package routes

import (
	"boilerplate/app/controllers"
	"boilerplate/app/middleware"

	"github.com/gofiber/fiber/v3"
)

// SetupAPI registers API routes
func SetupAPI(app *fiber.App) {
	v1 := app.Group("/api/v1")
	
	// Link endpoints (requires API token)
	links := v1.Group("/links", middleware.RequireAPIToken)
	links.Post("/", controllers.CreateShortLink)
	links.Put("/", controllers.UpdateLinkByURL)
	links.Delete("/", controllers.DeleteLinkByURL)
}

