package middleware

import (
	"github.com/gofiber/fiber/v3"
)

const (
	adminSessionKey  = "admin_authenticated"
	adminUsernameKey = "admin_username"
)

// RequireAdminAuth middleware checks if user is authenticated as admin
func RequireAdminAuth(c fiber.Ctx) error {
	// Check session cookie
	authenticated := c.Cookies(adminSessionKey)

	if authenticated == "" || authenticated != "true" {
		return c.Redirect().To("/admin/login")
	}

	return c.Next()
}
