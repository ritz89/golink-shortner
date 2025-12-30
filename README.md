# onjourney.link

High-performance URL Shortener built with Go Fiber, PostgreSQL, and RabbitMQ.

## Features

- **Short Link Creation**: Create short links via API with optional custom codes
- **Link Redirection**: Fast URL redirection with click event tracking
- **API Token Management**: Secure API access with configurable tokens
- **RabbitMQ Integration**: Publish click events to RabbitMQ with per-token configuration
- **Rate Limiting**: Bot protection with configurable rate limits (default: 1 publish/minute per session)
- **Admin Panel**: Web UI for managing links and API tokens with Tailwind CSS
- **Swagger Documentation**: API documentation available at `/swagger.json`

## Tech Stack

- **Framework**: Go Fiber v3
- **Database**: PostgreSQL with GORM
- **Message Queue**: RabbitMQ (amqp091-go)
- **UI**: Server-Side Rendering with HTML templates + Tailwind CSS
- **Authentication**: Session-based cookies for admin, API tokens for API access

## Prerequisites

- Go 1.20 or higher
- PostgreSQL
- RabbitMQ (optional, for click event tracking)

## Configuration

The application uses environment variables for configuration. Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

### Required Environment Variables

- `DB_HOST` - PostgreSQL host (default: `localhost`)
- `DB_PORT` - PostgreSQL port (default: `5432`)
- `DB_USER` - PostgreSQL user (default: `postgres`)
- `DB_PASSWORD` - PostgreSQL password (**required**, no default)
- `DB_NAME` - Database name (default: `link_shorner`)
- `DB_SSLMODE` - SSL mode (default: `disable`)
- `DB_TIMEZONE` - Timezone (default: `Asia/Jakarta`)

**Note:** RabbitMQ configuration is stored per API token in the database, not in environment variables. Each API token can have its own RabbitMQ broker configuration for maximum flexibility.

## Database Setup

1. Create PostgreSQL database:
```sql
CREATE DATABASE link_shorner;
```

2. Set environment variables (or use `.env` file):
```bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_USER=postgres
export DB_PASSWORD=your_password
export DB_NAME=link_shorner
```

3. The application will automatically:
   - Run database migrations on startup
   - Create default admin user (username: `admin`, password: `admin123`)
   - ⚠️ **IMPORTANT**: Change the default admin password in production!

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd golink-shorner
```

2. Install dependencies:
```bash
go mod download
```

3. Configure environment variables (see Configuration section above)

## Running the Application

### Development Mode

```bash
go run app.go
```

The server will start on `http://localhost:3000`

### Production Mode

```bash
go run app.go -prod
```

Or build and run:
```bash
go build -o golink-shorner app.go
./golink-shorner -prod
```

## Usage

### Admin Panel

1. Access admin login: `http://localhost:3000/admin/login`
2. Default credentials:
   - Username: `admin`
   - Password: `admin123`
3. After login, you can:
   - View dashboard with statistics
   - Manage short links (create, edit, delete)
   - Manage API tokens (create, configure RabbitMQ, set rate limits)

### API Endpoints

#### Create Short Link

```bash
POST /api/v1/links
Headers:
  X-API-Token: <your-api-token>

Body:
{
  "original_url": "https://example.com",
  "code": "optional-custom-code"  // optional, 4-20 alphanumeric chars
}

Response:
{
  "success": true,
  "data": {
    "code": "abc123",
    "original_url": "https://example.com",
    "short_url": "http://localhost:3000/abc123"
  }
}
```

#### Redirect to Original URL

```
GET /:code
```

Automatically redirects to the original URL and publishes click event to RabbitMQ (if configured and rate limit allows).

#### Admin API Endpoints

All admin endpoints require authentication via session cookie:

- `GET /api/v1/admin/links` - List all links
- `POST /api/v1/admin/links` - Create link (admin)
- `PUT /api/v1/admin/links/:code` - Update link
- `DELETE /api/v1/admin/links/:code` - Delete link
- `GET /api/v1/admin/tokens` - List API tokens
- `POST /api/v1/admin/tokens` - Create API token
- `PUT /api/v1/admin/tokens/:id` - Update API token
- `DELETE /api/v1/admin/tokens/:id` - Delete API token

### Rate Limiting

Each API token can be configured with a `rate_limit_seconds` value (default: 60 seconds). When a user clicks a short link:
- The system generates a session key from IP + User-Agent
- Click events are published to RabbitMQ only once per `rate_limit_seconds` per session
- Subsequent clicks from the same session within the time window are silently ignored

This prevents bot spam while still tracking legitimate user clicks.

### RabbitMQ Configuration

**RabbitMQ configuration is stored per API token in the database**, allowing each client to use their own RabbitMQ broker. This provides maximum flexibility for multi-tenant scenarios.

Each API token can have its own RabbitMQ configuration:
- **Host** - RabbitMQ broker host
- **Port** - RabbitMQ broker port (default: `5672`)
- **User** - RabbitMQ username
- **Password** - RabbitMQ password
- **Queue name** - Queue name for click events (default: `click_events`)

The system automatically manages connections to different RabbitMQ brokers using a connection pool. Connections are reused per broker configuration.

Click events are published as JSON:

```json
{
  "code": "abc123",
  "original_url": "https://example.com",
  "clicked_at": "2024-01-01T00:00:00Z",
  "ip": "127.0.0.1",
  "user_agent": "Mozilla/5.0..."
}
```

## Project Structure

```
golink-shorner/
├── app/
│   ├── controllers/     # HTTP handlers
│   ├── middleware/      # Authentication & API token middleware
│   ├── models/          # GORM models
│   └── queries/         # Database operations
├── platform/
│   ├── database/        # Database connection & migrations
│   └── queue/           # RabbitMQ connection & publishing
├── pkg/
│   ├── ratelimiter/     # Rate limiting logic
│   ├── routes/          # Route definitions
│   └── utils/           # Utilities (short code generation)
├── views/               # HTML templates
├── docs/                # Swagger documentation
└── app.go               # Main application file
```

## Development

### Database Migrations

Migrations run automatically on application startup. The application will:
1. Connect to PostgreSQL
2. Run `AutoMigrate` on all models
3. Seed default admin user if not exists

### Adding New Models

1. Create model in `app/models/`
2. Add to `AutoMigrate` in `platform/database/database.go`
3. Create query struct in `app/queries/`
4. Create controller in `app/controllers/`
5. Register routes in `pkg/routes/`

## Docker (Optional)

Build Docker image:
```bash
docker build -t golink-shorner .
```

Run container:
```bash
docker run -d -p 3000:3000 \
  -e DB_HOST=host.docker.internal \
  -e DB_PORT=5432 \
  -e DB_USER=postgres \
  -e DB_PASSWORD=your_password \
  -e DB_NAME=link_shorner \
  -e DB_SSLMODE=disable \
  -e DB_TIMEZONE=Asia/Jakarta \
  golink-shorner ./app -prod
```

**Note:** RabbitMQ configuration is configured per API token via the admin panel, not via environment variables.

## API Documentation

Swagger documentation is available at:
- JSON: `http://localhost:3000/swagger.json`

## Health Check

```bash
GET /health
```

Returns:
```json
{
  "status": "ok"
}
```

## Security Notes

- Default admin password should be changed immediately in production
- API tokens should be kept secure
- Use HTTPS in production
- Configure proper CORS settings if needed
- Rate limiting helps prevent abuse but should be tuned per use case

## License

Copyright (c) 2024 On-journey. All Rights Reserved.

This software is proprietary and confidential. Unauthorized copying, modification, 
distribution, or use of this software, via any medium, is strictly prohibited 
without the express written permission of On-journey.

See LICENSE file for details.
