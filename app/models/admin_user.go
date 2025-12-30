package models

// AdminUser model untuk admin authentication
type AdminUser struct {
	Base
	Username     string `gorm:"uniqueIndex;not null" json:"username"`
	PasswordHash string `gorm:"not null;type:varchar(255)" json:"-"`
}

// TableName mengembalikan nama table
func (AdminUser) TableName() string {
	return "admin_users"
}
