package queue

import (
	"boilerplate/app/models"
	"boilerplate/pkg/ratelimiter"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"strings"
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
	return fmt.Sprintf("%s:%d:%s:%s", token.RabbitMQHost, token.RabbitMQPort, token.RabbitMQUser, token.RabbitMQVHost)
}

// buildAMQPURL builds AMQP connection URL from token config
func buildAMQPURL(token *models.APIToken) string {
	port := token.RabbitMQPort
	if port == 0 {
		port = 5672
	}

	// Normalize vhost - ensure it starts with /
	vhost := token.RabbitMQVHost
	if vhost == "" {
		vhost = "/"
	} else if !strings.HasPrefix(vhost, "/") {
		vhost = "/" + vhost
	}

	// URL encode user and password only if they contain special characters
	// For most cases, we don't need to encode, but url.QueryEscape handles it safely
	encodedUser := url.QueryEscape(token.RabbitMQUser)
	encodedPassword := url.QueryEscape(token.RabbitMQPassword)

	// For vhost in AMQP URL path:
	// - Default vhost "/" uses "/" in URL
	// - Custom vhost "/onjourney_prod" uses "/onjourney_prod" in URL (vhost name without leading slash)
	//   OR uses "%2Fonjourney_prod" (encoded leading slash + vhost name)
	// Based on RabbitMQ docs, custom vhost should be: /vhostname (path separator + vhost name)
	var encodedVHost string
	if vhost == "/" {
		// Default vhost
		encodedVHost = "/"
	} else {
		// Custom vhost: use vhost name without leading slash in URL path
		// Format: /vhostname (not /%2Fvhostname)
		// Example: /onjourney_prod becomes /onjourney_prod
		vhostName := strings.TrimPrefix(vhost, "/")
		// URL encode only if vhost name contains special characters
		encodedVHostName := url.PathEscape(vhostName)
		encodedVHost = "/" + encodedVHostName
	}

	return fmt.Sprintf("amqp://%s:%s@%s:%d%s",
		encodedUser,
		encodedPassword,
		token.RabbitMQHost,
		port,
		encodedVHost,
	)
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

	// Build AMQP URL from token config (without vhost in URL for custom vhosts)
	// We'll use DialConfig to set vhost explicitly
	port := token.RabbitMQPort
	if port == 0 {
		port = 5672
	}

	// Build base URL without vhost
	encodedUser := url.QueryEscape(token.RabbitMQUser)
	encodedPassword := url.QueryEscape(token.RabbitMQPassword)
	baseURL := fmt.Sprintf("amqp://%s:%s@%s:%d/",
		encodedUser,
		encodedPassword,
		token.RabbitMQHost,
		port,
	)

	// Normalize vhost
	vhost := token.RabbitMQVHost
	if vhost == "" {
		vhost = "/"
	} else if !strings.HasPrefix(vhost, "/") {
		vhost = "/" + vhost
	}

	// Log connection attempt
	log.Printf("Connecting to RabbitMQ: %s@%s:%d, vhost: %s",
		token.RabbitMQUser, token.RabbitMQHost, token.RabbitMQPort, vhost)

	// Use DialConfig to set vhost explicitly
	conn, err := amqp.DialConfig(baseURL, amqp.Config{
		Vhost: vhost,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to connect to RabbitMQ (vhost: %s): %w", token.RabbitMQVHost, err)
	}

	channel, err := conn.Channel()
	if err != nil {
		if closeErr := conn.Close(); closeErr != nil {
			log.Printf("Failed to close connection after channel error: %v", closeErr)
		}
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
	if rateLimitSeconds < 0 {
		rateLimitSeconds = 0
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
			if err := conn.channel.Close(); err != nil {
				log.Printf("Failed to close channel for key %s: %v", key, err)
			}
		}
		if conn.conn != nil {
			if err := conn.conn.Close(); err != nil {
				log.Printf("Failed to close connection for key %s: %v", key, err)
			}
		}
		delete(pool.pools, key)
	}
}

// TestConnection tests RabbitMQ connection for a token
// Creates a new connection (not from pool) and closes it after test
func TestConnection(token *models.APIToken) error {
	// Validate RabbitMQ config
	if token.RabbitMQHost == "" {
		return fmt.Errorf("RabbitMQ host not configured")
	}
	if token.RabbitMQUser == "" {
		return fmt.Errorf("RabbitMQ user not configured")
	}

	// Build base URL and set vhost explicitly
	port := token.RabbitMQPort
	if port == 0 {
		port = 5672
	}

	encodedUser := url.QueryEscape(token.RabbitMQUser)
	encodedPassword := url.QueryEscape(token.RabbitMQPassword)
	baseURL := fmt.Sprintf("amqp://%s:%s@%s:%d/",
		encodedUser,
		encodedPassword,
		token.RabbitMQHost,
		port,
	)

	// Normalize vhost
	vhost := token.RabbitMQVHost
	if vhost == "" {
		vhost = "/"
	} else if !strings.HasPrefix(vhost, "/") {
		vhost = "/" + vhost
	}

	// Log connection attempt
	log.Printf("Testing RabbitMQ connection: %s@%s:%d, vhost: %s",
		token.RabbitMQUser, token.RabbitMQHost, token.RabbitMQPort, vhost)

	// Create connection (with timeout handled by context)
	done := make(chan error, 1)
	var conn *amqp.Connection
	var err error

	go func() {
		conn, err = amqp.DialConfig(baseURL, amqp.Config{
			Vhost: vhost,
		})
		done <- err
	}()

	select {
	case err := <-done:
		if err != nil {
			return fmt.Errorf("failed to connect to RabbitMQ (vhost: %s): %w", token.RabbitMQVHost, err)
		}
	case <-time.After(10 * time.Second):
		return fmt.Errorf("connection test timeout after 10 seconds")
	}

	defer func() {
		if conn != nil {
			if err := conn.Close(); err != nil {
				log.Printf("Failed to close test connection: %v", err)
			}
		}
	}()

	// Test channel creation
	channel, err := conn.Channel()
	if err != nil {
		return fmt.Errorf("failed to open channel: %w", err)
	}
	defer func() {
		if err := channel.Close(); err != nil {
			log.Printf("Failed to close test channel: %v", err)
		}
	}()

	// Connection successful
	return nil
}

// TestPublish tests publishing a message to RabbitMQ for a token
// Creates a new connection (not from pool) and closes it after test
func TestPublish(token *models.APIToken) error {
	// Validate RabbitMQ config
	if token.RabbitMQHost == "" {
		return fmt.Errorf("RabbitMQ host not configured")
	}
	if token.RabbitMQUser == "" {
		return fmt.Errorf("RabbitMQ user not configured")
	}

	// Build base URL and set vhost explicitly
	port := token.RabbitMQPort
	if port == 0 {
		port = 5672
	}

	encodedUser := url.QueryEscape(token.RabbitMQUser)
	encodedPassword := url.QueryEscape(token.RabbitMQPassword)
	baseURL := fmt.Sprintf("amqp://%s:%s@%s:%d/",
		encodedUser,
		encodedPassword,
		token.RabbitMQHost,
		port,
	)

	// Normalize vhost
	vhost := token.RabbitMQVHost
	if vhost == "" {
		vhost = "/"
	} else if !strings.HasPrefix(vhost, "/") {
		vhost = "/" + vhost
	}

	// Log connection attempt
	log.Printf("Testing RabbitMQ publish: %s@%s:%d, vhost: %s",
		token.RabbitMQUser, token.RabbitMQHost, token.RabbitMQPort, vhost)

	// Create connection (with timeout handled by goroutine)
	done := make(chan error, 1)
	var conn *amqp.Connection
	var err error

	go func() {
		conn, err = amqp.DialConfig(baseURL, amqp.Config{
			Vhost: vhost,
		})
		done <- err
	}()

	select {
	case err := <-done:
		if err != nil {
			return fmt.Errorf("failed to connect to RabbitMQ (vhost: %s): %w", token.RabbitMQVHost, err)
		}
	case <-time.After(10 * time.Second):
		return fmt.Errorf("connection test timeout after 10 seconds")
	}

	defer func() {
		if conn != nil {
			if err := conn.Close(); err != nil {
				log.Printf("Failed to close test connection: %v", err)
			}
		}
	}()

	// Open channel
	channel, err := conn.Channel()
	if err != nil {
		return fmt.Errorf("failed to open channel: %w", err)
	}
	defer func() {
		if err := channel.Close(); err != nil {
			log.Printf("Failed to close test channel: %v", err)
		}
	}()

	// Get queue name
	queueName := token.RabbitMQQueue
	if queueName == "" {
		queueName = "click_events"
	}

	// Declare queue
	_, err = channel.QueueDeclare(
		queueName,
		true,  // durable
		false, // delete when unused
		false, // exclusive
		false, // no-wait
		nil,   // arguments
	)
	if err != nil {
		return fmt.Errorf("failed to declare queue: %w", err)
	}

	// Prepare test message
	testMessage := map[string]interface{}{
		"test":      true,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"message":   "Test message from golink-shortener",
	}

	messageJSON, err := json.Marshal(testMessage)
	if err != nil {
		return fmt.Errorf("failed to marshal test message: %w", err)
	}

	// Publish test message with timeout
	publishCtx, publishCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer publishCancel()

	err = channel.PublishWithContext(
		publishCtx,
		"",        // exchange
		queueName, // routing key
		false,     // mandatory
		false,     // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        messageJSON,
		},
	)

	if err != nil {
		return fmt.Errorf("failed to publish test message: %w", err)
	}

	// Publish successful
	return nil
}
