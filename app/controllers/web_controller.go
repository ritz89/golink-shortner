package controllers

import (
	"boilerplate/app/models"
	"boilerplate/app/queries"
	"boilerplate/platform/database"
	"boilerplate/pkg/utils"

	"github.com/gofiber/fiber/v3"
)

// ShortenRequest request struct for web UI shorten
type ShortenRequest struct {
	OriginalURL string `json:"original_url" validate:"required,url"`
	Code        string `json:"code,omitempty" validate:"omitempty,min=4,max=20"`
}

// IndexPage handles GET /
func IndexPage(c fiber.Ctx) error {
	return c.Render("index", fiber.Map{
		"Title": "onjourney.link - URL Shortener",
	})
}

// ShortenURL handles POST /shorten (public web UI)
func ShortenURL(c fiber.Ctx) error {
	var req ShortenRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"success": false,
			"error":   "Invalid request body",
		})
	}

	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}

	// Generate code if not provided
	code := req.Code
	if code == "" {
		code = utils.GenerateShortCode()
		// Ensure uniqueness
		for {
			exists, err := linkQuery.Exists(code)
			if err != nil {
				return c.Status(500).JSON(fiber.Map{
					"success": false,
					"error":   "Failed to check code uniqueness",
				})
			}
			if !exists {
				break
			}
			code = utils.GenerateShortCode()
		}
	} else {
		// Validate custom code
		if !utils.ValidateCode(code) {
			return c.Status(400).JSON(fiber.Map{
				"success": false,
				"error":   "Invalid code format. Use 4-20 alphanumeric characters, hyphens, or underscores",
			})
		}

		// Check if code exists
		exists, err := linkQuery.Exists(code)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{
				"success": false,
				"error":   "Failed to check code",
			})
		}
		if exists {
			return c.Status(409).JSON(fiber.Map{
				"success": false,
				"error":   "This custom code is already taken. Please choose another one.",
			})
		}
	}

	// Create link (not from API, so IsAPIGenerated = false)
	link := &models.Link{
		Code:            code,
		OriginalURL:     req.OriginalURL,
		IsAPIGenerated:  false,
	}

	if err := linkQuery.Create(link); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"success": false,
			"error":   "Failed to create link",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
		"data": fiber.Map{
			"code":         link.Code,
			"original_url": link.OriginalURL,
			"short_url":    c.BaseURL() + "/" + link.Code,
		},
	})
}

