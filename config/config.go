package config

import (
	"fmt"
	"os"
)

type DatabaseConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	DBName   string
	SSLMode  string
}

var DB *DatabaseConfig

// Load reads environment variables and initializes config
func Load() {
	DB = &DatabaseConfig{
		Host:     getEnv("DB_HOST", "localhost"),
		Port:     getEnv("DB_PORT", "5432"),
		User:     getEnv("DB_USER", "postgres"),
		Password: getEnv("DB_PASSWORD", ""),
		DBName:   getEnv("DB_NAME", "link_shorner"),
		SSLMode:  getEnv("DB_SSLMODE", "disable"),
	}

	// Validate required database config
	if DB.Password == "" {
		panic("DB_PASSWORD environment variable is required")
	}
}

// GetDSN returns PostgreSQL connection string
func (db *DatabaseConfig) GetDSN() string {
	return fmt.Sprintf(
		"host=%s user=%s password=%s dbname=%s port=%s sslmode=%s",
		db.Host, db.User, db.Password, db.DBName, db.Port, db.SSLMode,
	)
}

// getEnv gets environment variable or returns default value
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
