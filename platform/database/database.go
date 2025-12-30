package database

import (
	"boilerplate/app/models"
	"boilerplate/config"
	"fmt"
	"log"

	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

var DB *gorm.DB

// Connect menghubungkan ke database PostgreSQL
func Connect() {
	dsn := config.DB.GetDSN()

	var err error
	DB, err = gorm.Open(postgres.Open(dsn), &gorm.Config{
		Logger: logger.Default.LogMode(logger.Info),
	})

	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}

	fmt.Println("Connected to PostgreSQL database")

	// Auto migrate models
	err = DB.AutoMigrate(
		&models.AdminUser{},
		&models.APIToken{},
		&models.Link{},
	)

	if err != nil {
		log.Fatal("Failed to migrate database:", err)
	}

	fmt.Println("Database migration completed")

	// Seed default data
	if err := Seed(DB); err != nil {
		log.Printf("Warning: Failed to seed database: %v", err)
	}
}

// GetDB mengembalikan instance database
func GetDB() *gorm.DB {
	return DB
}
