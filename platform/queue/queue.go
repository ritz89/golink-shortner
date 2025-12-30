package queue

import (
	"boilerplate/app/models"
	"boilerplate/pkg/ratelimiter"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"sync"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

// connectionPool stores connections per token config
type connectionPool struct {
	mu    sync.RWMutex
	pools map[string]*tokenConnection
}

type tokenConnection struct {
	conn    *amqp.Connection
	channel *amqp.Channel
}

var pool = &connectionPool{
	pools: make(map[string]*tokenConnection),
}

// getConnectionKey generates a unique key for token's RabbitMQ config
func getConnectionKey(token *models.APIToken) string {
	return fmt.Sprintf("%s:%d:%s", token.RabbitMQHost, token.RabbitMQPort, token.RabbitMQUser)
}

// getOrCreateConnection gets or creates a RabbitMQ connection for the token
func getOrCreateConnection(token *models.APIToken) (*amqp.Channel, error) {
	// Check if token has RabbitMQ config
	if token.RabbitMQHost == "" {
		return nil, fmt.Errorf("RabbitMQ host not configured for token")
	}

	key := getConnectionKey(token)

	pool.mu.RLock()
	if conn, exists := pool.pools[key]; exists {
		// Check if connection is still valid
		if conn.channel != nil && !conn.channel.IsClosed() {
			pool.mu.RUnlock()
			return conn.channel, nil
		}
		// Connection is closed, remove from pool
		delete(pool.pools, key)
	}
	pool.mu.RUnlock()

	// Create new connection
	pool.mu.Lock()
	defer pool.mu.Unlock()

	// Double check after acquiring write lock
	if conn, exists := pool.pools[key]; exists && conn.channel != nil && !conn.channel.IsClosed() {
		return conn.channel, nil
	}

	// Build AMQP URL from token config
	port := token.RabbitMQPort
	if port == 0 {
		port = 5672
	}

	amqpURL := fmt.Sprintf("amqp://%s:%s@%s:%d/",
		token.RabbitMQUser,
		token.RabbitMQPassword,
		token.RabbitMQHost,
		port,
	)

	conn, err := amqp.Dial(amqpURL)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ: %w", err)
	}

	channel, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("failed to open channel: %w", err)
	}

	pool.pools[key] = &tokenConnection{
		conn:    conn,
		channel: channel,
	}

	return channel, nil
}

// PublishClickEvent publishes a click event to RabbitMQ with rate limiting
func PublishClickEvent(token *models.APIToken, code, originalURL, ip, userAgent string, rateLimiter *ratelimiter.RateLimiter) {
	// Generate session key
	sessionKey := ratelimiter.GetSessionKey(ip, userAgent)

	// Get rate limit seconds (default 60 if not set)
	rateLimitSeconds := token.RateLimitSeconds
	if rateLimitSeconds <= 0 {
		rateLimitSeconds = 60
	}

	// Check if publish is allowed
	if !rateLimiter.ShouldAllowPublish(sessionKey, rateLimitSeconds) {
		// Silent fail - rate limited, don't publish
		return
	}

	// Record publish time
	rateLimiter.RecordPublish(sessionKey)

	// Create context with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Prepare event payload
	event := map[string]interface{}{
		"code":         code,
		"original_url": originalURL,
		"clicked_at":   time.Now().UTC().Format(time.RFC3339),
		"ip":           ip,
		"user_agent":   userAgent,
	}

	eventJSON, err := json.Marshal(event)
	if err != nil {
		log.Printf("Failed to marshal event: %v", err)
		return
	}

	// Get or create connection for this token
	channel, err := getOrCreateConnection(token)
	if err != nil {
		log.Printf("Failed to get RabbitMQ connection: %v", err)
		return
	}

	// Use token's RabbitMQ config or default
	queueName := token.RabbitMQQueue
	if queueName == "" {
		queueName = "click_events"
	}

	// Ensure queue exists
	_, err = channel.QueueDeclare(
		queueName,
		true,  // durable
		false, // delete when unused
		false, // exclusive
		false, // no-wait
		nil,   // arguments
	)
	if err != nil {
		log.Printf("Failed to declare queue: %v", err)
		return
	}

	// Publish message
	err = channel.PublishWithContext(
		ctx,
		"",        // exchange
		queueName, // routing key
		false,     // mandatory
		false,     // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        eventJSON,
		},
	)

	if err != nil {
		log.Printf("Failed to publish message: %v", err)
	}
}

// Close closes all RabbitMQ connections
func Close() {
	pool.mu.Lock()
	defer pool.mu.Unlock()

	for key, conn := range pool.pools {
		if conn.channel != nil {
			conn.channel.Close()
		}
		if conn.conn != nil {
			conn.conn.Close()
		}
		delete(pool.pools, key)
	}
}
