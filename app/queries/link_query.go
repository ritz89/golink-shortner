package queries

import (
	"boilerplate/app/models"

	"gorm.io/gorm"
)

// LinkQuery handles database operations for links
type LinkQuery struct {
	DB *gorm.DB
}

// GetByCode retrieves a link by its short code
func (q *LinkQuery) GetByCode(code string) (*models.Link, error) {
	var link models.Link
	err := q.DB.Preload("APIToken").Where("code = ?", code).First(&link).Error
	if err != nil {
		return nil, err
	}
	return &link, nil
}

// Create creates a new link
func (q *LinkQuery) Create(link *models.Link) error {
	return q.DB.Create(link).Error
}

// List retrieves all links with pagination and optional search
func (q *LinkQuery) List(limit, offset int, search string) ([]models.Link, int64, error) {
	var links []models.Link
	var count int64

	query := q.DB.Model(&models.Link{})

	// Apply search filter if provided
	if search != "" {
		searchPattern := "%" + search + "%"
		query = query.Where("code LIKE ? OR original_url LIKE ?", searchPattern, searchPattern)
	}

	if err := query.Count(&count).Error; err != nil {
		return nil, 0, err
	}

	query = query.Preload("APIToken").Limit(limit).Offset(offset).Order("created_at DESC")
	err := query.Find(&links).Error
	return links, count, err
}

// Delete soft deletes a link by code
func (q *LinkQuery) Delete(code string) error {
	return q.DB.Where("code = ?", code).Delete(&models.Link{}).Error
}

// Update updates a link by code
func (q *LinkQuery) Update(code string, link *models.Link) error {
	return q.DB.Model(&models.Link{}).Where("code = ?", code).Updates(link).Error
}

// Exists checks if a code already exists
func (q *LinkQuery) Exists(code string) (bool, error) {
	var count int64
	err := q.DB.Model(&models.Link{}).Where("code = ?", code).Count(&count).Error
	if err != nil {
		return false, err
	}
	return count > 0, nil
}
