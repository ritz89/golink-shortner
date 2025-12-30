package controllers

import (
	"boilerplate/app/models"
	"boilerplate/app/queries"
	"boilerplate/platform/database"

	"github.com/gofiber/fiber/v3"
)

// CreateAdminUserRequest request struct for creating admin user
type CreateAdminUserRequest struct {
	Username string `json:"username" validate:"required"`
	Password string `json:"password" validate:"required,min=6"`
}

// UpdateAdminUserRequest request struct for updating admin user
type UpdateAdminUserRequest struct {
	Username string `json:"username"`
	Password string `json:"password" validate:"omitempty,min=6"`
}

// ListAdminUsers handles GET /api/v1/admin/users
func ListAdminUsers(c fiber.Ctx) error {
	db := database.GetDB()
	userQuery := &queries.AdminUserQuery{DB: db}

	users, err := userQuery.List()
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to list users",
		})
	}

	// Remove password hash from response
	responseUsers := make([]fiber.Map, len(users))
	for i, user := range users {
		responseUsers[i] = fiber.Map{
			"id":        user.ID,
			"username":  user.Username,
			"created_at": user.CreatedAt,
		}
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data":    responseUsers,
	})
}

// CreateAdminUser handles POST /api/v1/admin/users
func CreateAdminUser(c fiber.Ctx) error {
	var req CreateAdminUserRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	db := database.GetDB()
	userQuery := &queries.AdminUserQuery{DB: db}

	// Check if username already exists
	_, err := userQuery.GetByUsername(req.Username)
	if err == nil {
		return c.Status(409).JSON(fiber.Map{
			"error": "Username already exists",
		})
	}

	user := &models.AdminUser{
		Username: req.Username,
	}

	if err := userQuery.Create(user, req.Password); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to create user",
		})
	}

	return c.Status(201).JSON(fiber.Map{
		"success": true,
		"data": fiber.Map{
			"id":        user.ID,
			"username":  user.Username,
			"created_at": user.CreatedAt,
		},
	})
}

// UpdateAdminUser handles PUT /api/v1/admin/users/:id
func UpdateAdminUser(c fiber.Ctx) error {
	id := fiber.Params[int](c, "id")
	if id == 0 {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid user ID",
		})
	}

	var req UpdateAdminUserRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	db := database.GetDB()
	userQuery := &queries.AdminUserQuery{DB: db}

	// Get existing user
	existingUser, err := userQuery.GetByID(uint(id))
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"error": "User not found",
		})
	}

	// Update username if provided
	if req.Username != "" {
		// Check if new username already exists (excluding current user)
		existingWithUsername, err := userQuery.GetByUsername(req.Username)
		if err == nil && existingWithUsername.ID != existingUser.ID {
			return c.Status(409).JSON(fiber.Map{
				"error": "Username already exists",
			})
		}
		existingUser.Username = req.Username
	}

	if err := userQuery.Update(uint(id), existingUser, req.Password); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to update user",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data": fiber.Map{
			"id":        existingUser.ID,
			"username":  existingUser.Username,
			"created_at": existingUser.CreatedAt,
		},
	})
}

// DeleteAdminUser handles DELETE /api/v1/admin/users/:id
func DeleteAdminUser(c fiber.Ctx) error {
	id := fiber.Params[int](c, "id")
	if id == 0 {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid user ID",
		})
	}

	db := database.GetDB()
	userQuery := &queries.AdminUserQuery{DB: db}

	if err := userQuery.Delete(uint(id)); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to delete user",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "User deleted successfully",
	})
}

