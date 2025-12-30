package queries

import (
	"boilerplate/app/models"
	"errors"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// AdminUserQuery handles database operations for admin users
type AdminUserQuery struct {
	DB *gorm.DB
}

// GetByUsername retrieves an admin user by username
func (q *AdminUserQuery) GetByUsername(username string) (*models.AdminUser, error) {
	var user models.AdminUser
	err := q.DB.Where("username = ?", username).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

// Create creates a new admin user with hashed password
func (q *AdminUserQuery) Create(user *models.AdminUser, password string) error {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	user.PasswordHash = string(hashedPassword)
	return q.DB.Create(user).Error
}

// ValidatePassword verifies if the provided password matches the user's password
func (q *AdminUserQuery) ValidatePassword(user *models.AdminUser, password string) error {
	err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(password))
	if err != nil {
		return errors.New("invalid password")
	}
	return nil
}

// List retrieves all admin users
func (q *AdminUserQuery) List() ([]models.AdminUser, error) {
	var users []models.AdminUser
	err := q.DB.Order("created_at DESC").Find(&users).Error
	return users, err
}

// GetByID retrieves an admin user by ID
func (q *AdminUserQuery) GetByID(id uint) (*models.AdminUser, error) {
	var user models.AdminUser
	err := q.DB.Where("id = ?", id).First(&user).Error
	if err != nil {
		return nil, err
	}
	return &user, nil
}

// Update updates an admin user's password
func (q *AdminUserQuery) Update(id uint, user *models.AdminUser, newPassword string) error {
	if newPassword != "" {
		hashedPassword, err := bcrypt.GenerateFromPassword([]byte(newPassword), bcrypt.DefaultCost)
		if err != nil {
			return err
		}
		user.PasswordHash = string(hashedPassword)
	}
	return q.DB.Model(&models.AdminUser{}).Where("id = ?", id).Updates(user).Error
}

// Delete soft deletes an admin user
func (q *AdminUserQuery) Delete(id uint) error {
	return q.DB.Delete(&models.AdminUser{}, id).Error
}

