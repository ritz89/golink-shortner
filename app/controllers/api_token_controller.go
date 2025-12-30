package controllers

import (
	"boilerplate/app/models"
	"boilerplate/app/queries"
	"boilerplate/platform/database"

	"github.com/gofiber/fiber/v3"
	"github.com/google/uuid"
)

// CreateTokenRequest request struct for creating API token
type CreateTokenRequest struct {
	Name             string `json:"name" validate:"required"`
	RabbitMQHost     string `json:"rabbitmq_host"`
	RabbitMQPort     int    `json:"rabbitmq_port"`
	RabbitMQUser     string `json:"rabbitmq_user"`
	RabbitMQPassword string `json:"rabbitmq_password"`
	RabbitMQQueue    string `json:"rabbitmq_queue"`
	RateLimitSeconds int    `json:"rate_limit_seconds"`
}

// UpdateTokenRequest request struct for updating API token
type UpdateTokenRequest struct {
	Name             string `json:"name"`
	RabbitMQHost     string `json:"rabbitmq_host"`
	RabbitMQPort     int    `json:"rabbitmq_port"`
	RabbitMQUser     string `json:"rabbitmq_user"`
	RabbitMQPassword string `json:"rabbitmq_password"`
	RabbitMQQueue    string `json:"rabbitmq_queue"`
	RateLimitSeconds int    `json:"rate_limit_seconds"`
}

// CreateToken handles POST /api/v1/admin/tokens
func CreateToken(c fiber.Ctx) error {
	var req CreateTokenRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Set defaults
	if req.RabbitMQPort == 0 {
		req.RabbitMQPort = 5672
	}
	if req.RateLimitSeconds == 0 {
		req.RateLimitSeconds = 60
	}
	if req.RabbitMQQueue == "" {
		req.RabbitMQQueue = "click_events"
	}

	db := database.GetDB()
	tokenQuery := &queries.APITokenQuery{DB: db}

	// Generate token
	token := &models.APIToken{
		Token:            uuid.New().String(),
		Name:             req.Name,
		RabbitMQHost:     req.RabbitMQHost,
		RabbitMQPort:     req.RabbitMQPort,
		RabbitMQUser:     req.RabbitMQUser,
		RabbitMQPassword: req.RabbitMQPassword,
		RabbitMQQueue:    req.RabbitMQQueue,
		RateLimitSeconds: req.RateLimitSeconds,
	}

	if err := tokenQuery.Create(token); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to create token",
		})
	}

	return c.Status(201).JSON(fiber.Map{
		"success": true,
		"data":    token,
	})
}

// ListTokens handles GET /api/v1/admin/tokens
func ListTokens(c fiber.Ctx) error {
	db := database.GetDB()
	tokenQuery := &queries.APITokenQuery{DB: db}

	tokens, err := tokenQuery.List()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to list tokens",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data":    tokens,
	})
}

// UpdateToken handles PUT /api/v1/admin/tokens/:id
func UpdateToken(c fiber.Ctx) error {
	id := fiber.Params[int](c, "id")
	if id == 0 {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid token ID",
		})
	}

	var req UpdateTokenRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	db := database.GetDB()
	tokenQuery := &queries.APITokenQuery{DB: db}

	// Get existing token
	existingToken, err := tokenQuery.GetByID(uint(id))
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"error": "Token not found",
		})
	}

	// Update fields
	if req.Name != "" {
		existingToken.Name = req.Name
	}
	if req.RabbitMQHost != "" {
		existingToken.RabbitMQHost = req.RabbitMQHost
	}
	if req.RabbitMQPort > 0 {
		existingToken.RabbitMQPort = req.RabbitMQPort
	}
	if req.RabbitMQUser != "" {
		existingToken.RabbitMQUser = req.RabbitMQUser
	}
	if req.RabbitMQPassword != "" {
		existingToken.RabbitMQPassword = req.RabbitMQPassword
	}
	if req.RabbitMQQueue != "" {
		existingToken.RabbitMQQueue = req.RabbitMQQueue
	}
	if req.RateLimitSeconds > 0 {
		existingToken.RateLimitSeconds = req.RateLimitSeconds
	}

	if err := tokenQuery.Update(uint(id), existingToken); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to update token",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data":    existingToken,
	})
}

// DeleteToken handles DELETE /api/v1/admin/tokens/:id
func DeleteToken(c fiber.Ctx) error {
	id := fiber.Params[int](c, "id")
	if id == 0 {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid token ID",
		})
	}

	db := database.GetDB()
	tokenQuery := &queries.APITokenQuery{DB: db}

	if err := tokenQuery.Delete(uint(id)); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to delete token",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Token deleted successfully",
	})
}
