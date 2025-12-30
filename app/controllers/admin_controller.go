package controllers

import (
	"boilerplate/app/queries"
	"boilerplate/platform/database"

	"github.com/gofiber/fiber/v3"
)

// Dashboard handles GET /admin
func Dashboard(c fiber.Ctx) error {
	db := database.GetDB()
	linkQuery := &queries.LinkQuery{DB: db}
	tokenQuery := &queries.APITokenQuery{DB: db}

	// Get stats
	links, _, _ := linkQuery.List(10, 0, "")
	tokens, _ := tokenQuery.List()

	return c.Render("admin/dashboard", fiber.Map{
		"Title":  "Dashboard",
		"Links":  links,
		"Tokens": tokens,
	}, "layouts/base")
}

// LinksPage handles GET /admin/links
func LinksPage(c fiber.Ctx) error {
	return c.Render("admin/links", fiber.Map{
		"Title": "Manage Links",
	}, "layouts/base")
}

// TokensPage handles GET /admin/tokens
func TokensPage(c fiber.Ctx) error {
	return c.Render("admin/tokens", fiber.Map{
		"Title":   "Manage API Tokens",
		"BaseURL": c.BaseURL(),
	}, "layouts/base")
}

// UsersPage handles GET /admin/users
func UsersPage(c fiber.Ctx) error {
	return c.Render("admin/users", fiber.Map{
		"Title": "Manage Admin Users",
	}, "layouts/base")
}
