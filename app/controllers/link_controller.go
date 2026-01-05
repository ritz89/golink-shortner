package controllers

import (
	"boilerplate/app/models"
	"boilerplate/app/queries"
	"boilerplate/pkg/ratelimiter"
	"boilerplate/pkg/utils"
	"boilerplate/platform/database"
	"boilerplate/platform/queue"

	"github.com/gofiber/fiber/v3"
)

var globalRateLimiter *ratelimiter.RateLimiter

// InitRateLimiter initializes the global rate limiter
func InitRateLimiter() {
	globalRateLimiter = ratelimiter.NewRateLimiter()
}

// CreateShortLinkRequest request struct for creating short link
type CreateShortLinkRequest struct {
	OriginalURL string `json:"original_url" validate:"required,url"`
	Code        string `json:"code,omitempty" validate:"omitempty,min=4,max=20"`
}

// APIUpdateLinkRequest request struct for updating link via API
type APIUpdateLinkRequest struct {
	OriginalURL string `json:"original_url" validate:"required"`
	Code        string `json:"code" validate:"required,min=4,max=20"`
}

// APIDeleteLinkRequest request struct for deleting link via API
type APIDeleteLinkRequest struct {
	OriginalURL string `json:"original_url" validate:"required"`
}

// CreateShortLink handles POST /api/v1/links
func CreateShortLink(c fiber.Ctx) error {
	var req CreateShortLinkRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	// Get API token from middleware
	apiToken := c.Locals("api_token").(*models.APIToken)
	_ = apiToken // Use token if needed for future features

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
					"error": "Failed to check code uniqueness",
				})
			}
			if !exists {
				break
			}
			code = utils.GenerateShortCode()
		}
	} else {
		// Normalize code (spaces -> hyphens)
		code = utils.NormalizeCode(code)
		
		// Validate custom code
		if !utils.ValidateCode(code) {
			return c.Status(400).JSON(fiber.Map{
				"error": "Invalid code format",
			})
		}

		// Check if code exists
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

	// Create link (from API, so IsAPIGenerated = true)
	link := &models.Link{
		Code:            code,
		OriginalURL:     req.OriginalURL,
		IsAPIGenerated:  true,
		APITokenID:      &apiToken.ID,
	}

	if err := linkQuery.Create(link); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to create link",
		})
	}

	return c.Status(201).JSON(fiber.Map{
		"success": true,
		"data": fiber.Map{
			"code":         link.Code,
			"original_url": link.OriginalURL,
			"short_url":    c.BaseURL() + "/" + link.Code,
		},
	})
}

// Redirect handles GET /:code
func Redirect(c fiber.Ctx) error {
	code := c.Params("code")

	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}

	link, err := linkQuery.GetByCode(code)
	if err != nil {
		return c.Status(404).SendString("Link not found")
	}

	// Only publish to RabbitMQ if link was generated via API
	if link.IsAPIGenerated && link.APIToken != nil {
		// Copy values before goroutine (Fiber context reuse warning)
		ip := c.IP()
		userAgent := c.Get("User-Agent")
		codeCopy := code
		originalURL := link.OriginalURL
		apiTokenCopy := link.APIToken

		// Publish click event asynchronously with rate limiting
		go func() {
			queue.PublishClickEvent(apiTokenCopy, codeCopy, originalURL, ip, userAgent, globalRateLimiter)
		}()
	}

	return c.Redirect().To(link.OriginalURL)
}

// UpdateLinkByURL handles PUT /api/v1/links
func UpdateLinkByURL(c fiber.Ctx) error {
	var req APIUpdateLinkRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	apiToken := c.Locals("api_token").(*models.APIToken)
	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}

	// Normalize code (spaces -> hyphens)
	normalizedCode := utils.NormalizeCode(req.Code)

	// Validate code format
	if !utils.ValidateCode(normalizedCode) {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid code format",
		})
	}

	// Check if link exists for original URL and API token
	link, err := linkQuery.GetByOriginalURLAndTokenID(req.OriginalURL, apiToken.ID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"error": "Link not found",
		})
	}

	// If code is different, check if new code already exists
	oldCode := link.Code
	if link.Code != normalizedCode {
		exists, err := linkQuery.Exists(normalizedCode)
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

	// Update code (use old code to find record, then update with new code)
	link.Code = normalizedCode
	if err := linkQuery.Update(oldCode, link); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to update link",
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"success": true,
		"data": fiber.Map{
			"code":         link.Code,
			"original_url": link.OriginalURL,
			"short_url":    c.BaseURL() + "/" + link.Code,
		},
	})
}

// DeleteLinkByURL handles DELETE /api/v1/links
func DeleteLinkByURL(c fiber.Ctx) error {
	var req APIDeleteLinkRequest
	if err := c.Bind().Body(&req); err != nil {
		return c.Status(400).JSON(fiber.Map{
			"error": "Invalid request body",
		})
	}

	apiToken := c.Locals("api_token").(*models.APIToken)
	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}

	// Check if link exists for original URL and API token
	_, err := linkQuery.GetByOriginalURLAndTokenID(req.OriginalURL, apiToken.ID)
	if err != nil {
		return c.Status(404).JSON(fiber.Map{
			"error": "Link not found",
		})
	}

	// Soft delete link
	if err := linkQuery.DeleteByOriginalURLAndTokenID(req.OriginalURL, apiToken.ID); err != nil {
		return c.Status(500).JSON(fiber.Map{
			"error": "Failed to delete link",
		})
	}

	return c.Status(200).JSON(fiber.Map{
		"success": true,
		"message": "Link deleted successfully",
	})
}
