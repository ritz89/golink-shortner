package utils

import (
	"crypto/rand"
	"math/big"
	"regexp"
	"strings"
)

const (
	base62Chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
	defaultLength = 8
	minLength = 4
	maxLength = 20
)

// GenerateShortCode generates a random base62 code
func GenerateShortCode() string {
	return GenerateShortCodeWithLength(defaultLength)
}

// GenerateShortCodeWithLength generates a random base62 code with specified length
func GenerateShortCodeWithLength(length int) string {
	if length < minLength {
		length = minLength
	}
	if length > maxLength {
		length = maxLength
	}
	
	var result strings.Builder
	result.Grow(length)
	
	for i := 0; i < length; i++ {
		num, err := rand.Int(rand.Reader, big.NewInt(int64(len(base62Chars))))
		if err != nil {
			// Fallback to simple random
			num = big.NewInt(int64(i * 31 % len(base62Chars)))
		}
		result.WriteByte(base62Chars[num.Int64()])
	}
	
	return result.String()
}

// ValidateCode validates if a code matches the required format
func ValidateCode(code string) bool {
	if len(code) < minLength || len(code) > maxLength {
		return false
	}
	
	// Only alphanumeric characters allowed
	matched, _ := regexp.MatchString("^[a-zA-Z0-9]+$", code)
	return matched
}

