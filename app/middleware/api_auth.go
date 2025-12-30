package middleware

import (
	"boilerplate/app/queries"
	"boilerplate/platform/database"

	"github.com/gofiber/fiber/v3"
)

// RequireAPIToken middleware validates API token from header
func RequireAPIToken(c fiber.Ctx) error {
	token := c.Get("X-API-Token")
	if token == "" {
		return c.Status(401).JSON(fiber.Map{
			"error": "API token required",
		})
	}

	db := database.GetDB()
	tokenQuery := &queries.APITokenQuery{DB: db}

	apiToken, err := tokenQuery.GetByToken(token)
	if err != nil {
		return c.Status(401).JSON(fiber.Map{
			"error": "Invalid API token",
		})
	}

	// Store token in locals for use in handlers
	c.Locals("api_token", apiToken)

	return c.Next()
}
