package controllers

import (
	"boilerplate/app/models"
	"boilerplate/app/queries"
	"boilerplate/pkg/utils"
	"boilerplate/platform/database"

	"github.com/gofiber/fiber/v3"
)

// CreateLinkRequest request struct for creating link (admin)
type CreateLinkRequest struct {
	Code        string `json:"code,omitempty"`
	OriginalURL string `json:"original_url" validate:"required,url"`
}

// UpdateLinkRequest request struct for updating link
type UpdateLinkRequest struct {
	OriginalURL string `json:"original_url" validate:"required,url"`
}

// ListLinks handles GET /api/v1/admin/links
func ListLinks(c fiber.Ctx) error {
	limit := fiber.Query[int](c, "limit", 50)
	offset := fiber.Query[int](c, "offset", 0)
	search := fiber.Query[string](c, "search", "")
	
	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}
	
	links, total, err := linkQuery.List(limit, offset, search)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to list links",
		})
	}
	
	return c.JSON(fiber.Map{
		"success": true,
		"data":    links,
		"total":   total,
	})
}

// CreateLink handles POST /api/v1/admin/links
func CreateLink(c fiber.Ctx) error {
	var req CreateLinkRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}

	code := req.Code
	if code == "" {
		code = utils.GenerateShortCode()
		for {
			exists, err := linkQuery.Exists(code)
			if err != nil {
				return c.Status(500).JSON(fiber.Map{
					"error": "Failed to check code",
				})
			}
			if !exists {
				break
			}
			code = utils.GenerateShortCode()
		}
	} else {
		if !utils.ValidateCode(code) {
			return c.Status(400).JSON(fiber.Map{
				"error": "Invalid code format",
			})
		}

		exists, err := linkQuery.Exists(code)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{
				"error": "Failed to check code",
			})
		}
		if exists {
			return c.Status(409).JSON(fiber.Map{
				"error": "Code already exists",
			})
		}
	}

	link := &models.Link{
		Code:            code,
		OriginalURL:     req.OriginalURL,
		IsAPIGenerated:  false, // Admin created links are not from API
	}

	if err := linkQuery.Create(link); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to create link",
		})
	}

	return c.Status(201).JSON(fiber.Map{
		"success": true,
		"data":    link,
	})
}

// UpdateLink handles PUT /api/v1/admin/links/:code
func UpdateLink(c fiber.Ctx) error {
	code := c.Params("code")

	var req UpdateLinkRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}

	link := &models.Link{
		OriginalURL: req.OriginalURL,
	}

	if err := linkQuery.Update(code, link); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to update link",
		})
	}

	// Get updated link
	updatedLink, err := linkQuery.GetByCode(code)
	if err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to get updated link",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data":    updatedLink,
	})
}

// DeleteLink handles DELETE /api/v1/admin/links/:code
func DeleteLink(c fiber.Ctx) error {
	code := c.Params("code")

	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}

	if err := linkQuery.Delete(code); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to delete link",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"message": "Link deleted successfully",
	})
}
