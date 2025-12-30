package queries

import (
	"boilerplate/app/models"

	"gorm.io/gorm"
)

// APITokenQuery handles database operations for API tokens
type APITokenQuery struct {
	DB *gorm.DB
}

// GetByToken retrieves an API token by token string
func (q *APITokenQuery) GetByToken(token string) (*models.APIToken, error) {
	var apiToken models.APIToken
	err := q.DB.Where("token = ?", token).First(&apiToken).Error
	if err != nil {
		return nil, err
	}
	return &apiToken, nil
}

// Create creates a new API token
func (q *APITokenQuery) Create(token *models.APIToken) error {
	return q.DB.Create(token).Error
}

// List retrieves all API tokens
func (q *APITokenQuery) List() ([]models.APIToken, error) {
	var tokens []models.APIToken
	err := q.DB.Order("created_at DESC").Find(&tokens).Error
	return tokens, err
}

// GetByID retrieves an API token by ID
func (q *APITokenQuery) GetByID(id uint) (*models.APIToken, error) {
	var token models.APIToken
	err := q.DB.First(&token, id).Error
	if err != nil {
		return nil, err
	}
	return &token, nil
}

// Delete soft deletes an API token by ID
func (q *APITokenQuery) Delete(id uint) error {
	return q.DB.Delete(&models.APIToken{}, id).Error
}

// Update updates an API token
func (q *APITokenQuery) Update(id uint, token *models.APIToken) error {
	return q.DB.Model(&models.APIToken{}).Where("id = ?", id).Updates(token).Error
}
