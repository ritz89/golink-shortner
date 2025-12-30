package database

import (
	"boilerplate/app/models"
	"boilerplate/app/queries"
	"fmt"
	"log"

	"gorm.io/gorm"
)

// Seed initializes default data in the database
func Seed(db *gorm.DB) error {
	adminQuery := &queries.AdminUserQuery{DB: db}

	// Check if admin user already exists
	_, err := adminQuery.GetByUsername("admin")
	if err == nil {
		log.Println("Admin user already exists, skipping seed")
		return nil
	}

	// Create default admin user
	adminUser := &models.AdminUser{
		Username: "admin",
	}

	// Default password: admin123 (change this in production!)
	defaultPassword := "admin123"
	if err := adminQuery.Create(adminUser, defaultPassword); err != nil {
		return fmt.Errorf("failed to create admin user: %w", err)
	}

	log.Println("Default admin user created successfully")
	log.Println("Username: admin")
	log.Println("Password: admin123")
	log.Println("⚠️  WARNING: Please change the default password in production!")

	return nil
}
