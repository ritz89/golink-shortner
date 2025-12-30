package models

// APIToken model untuk API token dengan RabbitMQ config
type APIToken struct {
	Base
	Token            string `gorm:"uniqueIndex;not null" json:"token"`
	Name             string `gorm:"not null" json:"name"`
	RabbitMQHost     string `gorm:"type:varchar(255)" json:"rabbitmq_host"`
	RabbitMQPort     int    `gorm:"default:5672" json:"rabbitmq_port"`
	RabbitMQUser     string `gorm:"type:varchar(255)" json:"rabbitmq_user"`
	RabbitMQPassword string `gorm:"type:varchar(255)" json:"rabbitmq_password"`
	RabbitMQQueue    string `gorm:"type:varchar(255)" json:"rabbitmq_queue"`
	RateLimitSeconds int    `gorm:"default:60" json:"rate_limit_seconds"`
}

// TableName mengembalikan nama table
func (APIToken) TableName() string {
	return "api_tokens"
}
