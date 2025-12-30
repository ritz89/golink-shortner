package models

// Link model untuk short links
type Link struct {
	Base
	Code           string    `gorm:"uniqueIndex;not null;size:20" json:"code"`
	OriginalURL    string    `gorm:"not null;type:text" json:"original_url"`
	IsAPIGenerated bool      `gorm:"default:false;not null" json:"is_api_generated"`
	APITokenID     *uint     `gorm:"index" json:"api_token_id,omitempty"`
	APIToken       *APIToken `gorm:"foreignKey:APITokenID" json:"api_token,omitempty"`
}

// TableName mengembalikan nama table
func (Link) TableName() string {
	return "links"
}
