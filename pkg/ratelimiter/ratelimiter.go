package ratelimiter

import (
	"crypto/sha256"
	"fmt"
	"sync"
	"time"
)

// RateLimiter handles rate limiting for click events
type RateLimiter struct {
	store sync.Map // map[sessionKey]lastPublishTime (Unix seconds)
}

// NewRateLimiter creates a new rate limiter instance
func NewRateLimiter() *RateLimiter {
	rl := &RateLimiter{}
	// Start cleanup goroutine
	go rl.cleanup()
	return rl
}

// GetSessionKey generates a session key from IP and User-Agent
func GetSessionKey(ip, userAgent string) string {
	combined := fmt.Sprintf("%s|%s", ip, userAgent)
	hash := sha256.Sum256([]byte(combined))
	return fmt.Sprintf("%x", hash)
}

// ShouldAllowPublish checks if publishing is allowed for the given session
func (rl *RateLimiter) ShouldAllowPublish(sessionKey string, rateLimitSeconds int) bool {
	now := time.Now().Unix()
	
	value, exists := rl.store.Load(sessionKey)
	if !exists {
		return true
	}
	
	lastPublishTime, ok := value.(int64)
	if !ok {
		return true
	}
	
	elapsed := now - lastPublishTime
	return elapsed >= int64(rateLimitSeconds)
}

// RecordPublish records the publish time for a session
func (rl *RateLimiter) RecordPublish(sessionKey string) {
	now := time.Now().Unix()
	rl.store.Store(sessionKey, now)
}

// cleanup removes old entries to prevent memory leaks
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()
	
	for range ticker.C {
		now := time.Now().Unix()
		rl.store.Range(func(key, value interface{}) bool {
			lastPublishTime, ok := value.(int64)
			if !ok {
				rl.store.Delete(key)
				return true
			}
			
			// Delete entries older than 24 hours
			if now-lastPublishTime > 86400 {
				rl.store.Delete(key)
			}
			return true
		})
	}
}

