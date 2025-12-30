package routes

import (
	"boilerplate/app/controllers"
	"boilerplate/app/middleware"

	"github.com/gofiber/fiber/v3"
)

// SetupAdmin registers admin routes
func SetupAdmin(app *fiber.App) {
	// Admin UI routes (require authentication)
	admin := app.Group("/admin", middleware.RequireAdminAuth)
	admin.Get("/", controllers.Dashboard)
	admin.Get("/links", controllers.LinksPage)
	admin.Get("/tokens", controllers.TokensPage)
	admin.Get("/users", controllers.UsersPage)
	
	// Admin API routes (require authentication)
	adminAPI := app.Group("/api/v1/admin", middleware.RequireAdminAuth)
	
	// Links management
	linksAPI := adminAPI.Group("/links")
	linksAPI.Get("/", controllers.ListLinks)
	linksAPI.Post("/", controllers.CreateLink)
	linksAPI.Put("/:code", controllers.UpdateLink)
	linksAPI.Delete("/:code", controllers.DeleteLink)
	
	// API tokens management
	tokensAPI := adminAPI.Group("/tokens")
	tokensAPI.Get("/", controllers.ListTokens)
	tokensAPI.Post("/", controllers.CreateToken)
	tokensAPI.Put("/:id", controllers.UpdateToken)
	tokensAPI.Delete("/:id", controllers.DeleteToken)

	// Admin users management
	usersAPI := adminAPI.Group("/users")
	usersAPI.Get("/", controllers.ListAdminUsers)
	usersAPI.Post("/", controllers.CreateAdminUser)
	usersAPI.Put("/:id", controllers.UpdateAdminUser)
	usersAPI.Delete("/:id", controllers.DeleteAdminUser)
}

// SetupAuth registers authentication routes (public)
func SetupAuth(app *fiber.App) {
	auth := app.Group("/admin")
	auth.Post("/login", controllers.Login)
	auth.Post("/logout", controllers.Logout)
	
	// Login page (public)
	app.Get("/admin/login", func(c fiber.Ctx) error {
		return c.Render("admin/login", fiber.Map{
			"Title": "Admin Login",
		})
	})
}

