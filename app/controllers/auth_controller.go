package controllers

import (
	"boilerplate/app/queries"
	"boilerplate/platform/database"
	"time"

	"github.com/gofiber/fiber/v3"
)

// LoginRequest request struct for admin login
type LoginRequest struct {
	Username string `json:"username" validate:"required"`
	Password string `json:"password" validate:"required"`
}

// Login handles POST /admin/login
func Login(c fiber.Ctx) error {
	var req LoginRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	db := database.GetDB()
	userQuery := &queries.AdminUserQuery{DB: db}

	user, err := userQuery.GetByUsername(req.Username)
	if err != nil {
		return c.Status(401).JSON(fiber.Map{
			"error": "Invalid credentials",
		})
	}

	if err := userQuery.ValidatePassword(user, req.Password); err != nil {
		return c.Status(401).JSON(fiber.Map{
			"error": "Invalid credentials",
		})
	}

	// Set session cookie
	c.Cookie(&fiber.Cookie{
		Name:     "admin_authenticated",
		Value:    "true",
		HTTPOnly: true,
		SameSite: "Lax",
	})

	c.Cookie(&fiber.Cookie{
		Name:     "admin_username",
		Value:    user.Username,
		HTTPOnly: true,
		SameSite: "Lax",
	})

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Login successful",
	})
}

// Logout handles POST /admin/logout
func Logout(c fiber.Ctx) error {
	c.Cookie(&fiber.Cookie{
		Name:     "admin_authenticated",
		Value:    "",
		HTTPOnly: true,
		SameSite: "Lax",
		Expires:  time.Unix(0, 0),
	})

	c.Cookie(&fiber.Cookie{
		Name:     "admin_username",
		Value:    "",
		HTTPOnly: true,
		SameSite: "Lax",
		Expires:  time.Unix(0, 0),
	})

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Logout successful",
	})
}
