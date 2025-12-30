package main

import (
	"boilerplate/app/controllers"
	"boilerplate/config"
	"boilerplate/pkg/routes"
	"boilerplate/platform/database"

	"flag"
	"log"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/logger"
	"github.com/gofiber/fiber/v3/middleware/recover"
	"github.com/gofiber/fiber/v3/middleware/static"
	"github.com/gofiber/template/html/v2"
)

var (
	port = flag.String("port", ":3000", "Port to listen on")
	prod = flag.Bool("prod", false, "Enable prefork in Production")
)

func main() {
	// Parse command-line flags
	flag.Parse()

	// Load configuration from environment variables
	config.Load()

	// Initialize database
	database.Connect()

	// Initialize rate limiter
	controllers.InitRateLimiter()

	// Setup template engine
	engine := html.New("./views", ".html")
	engine.Reload(true) // Enable hot reload in development

	// Create fiber app
	app := fiber.New(fiber.Config{
		Views: engine,
	})

	// Middleware
	app.Use(recover.New())
	app.Use(logger.New())

	// Register specific routes first (more specific routes should be registered before catch-all)
	// Health check
	app.Get("/health", func(c fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status": "ok",
		})
	})

	// Swagger documentation
	app.Get("/swagger.json", func(c fiber.Ctx) error {
		return c.SendFile("./docs/swagger.yaml")
	})

	// Register API and admin routes
	routes.SetupAPI(app)
	routes.SetupAuth(app)
	routes.SetupAdmin(app)

	// Setup static files (before catch-all route)
	app.Use(static.New("./static/public"))

	// Register web routes (catch-all /:code route) - must be last
	routes.SetupWeb(app)

	// Handle not founds
	app.Use(func(c fiber.Ctx) error {
		return c.Status(404).SendString("Not Found")
	})

	// Listen on port
	log.Printf("Server starting on port %s", *port)
	log.Fatal(app.Listen(*port, fiber.ListenConfig{EnablePrefork: *prod}))
}
