# UI Documentation - Aether PDS Server

## Overview

A complete web UI has been added to the Aether PDS Server with user registration, OAuth login, and authorization consent pages. Built with Phoenix LiveView for real-time, interactive experiences.

## Pages Created

### 1. Home Page (`/`)
**File:** `lib/aether_pds_server_web/live/home_live.ex`

Landing page that provides:
- Server information
- Feature highlights
- API endpoint documentation
- Quick access to registration and login

**Features:**
- Clean, professional hero section
- Feature cards with icons
- API endpoint list
- Links to LiveDashboard and health check

### 2. Registration Page (`/register`)
**File:** `lib/aether_pds_server_web/live/register_live.ex`

User account creation with:
- Handle input (with @ prefix)
- Email input
- Password input (minimum 8 characters)
- Real-time form validation
- Success screen with DID display

**Flow:**
1. User fills out form
2. Form validates in real-time
3. On submit, creates account + repository
4. Shows success message with DID
5. Provides link to login page

**Error Handling:**
- Duplicate handle detection
- Missing required fields
- Changeset validation errors
- User-friendly error messages

### 3. Login Page (`/oauth/login`)
**File:** `lib/aether_pds_server_web/live/login_live.ex`

User authentication with dual modes:

**Direct Login Mode (no OAuth params):**
- User enters handle or email + password
- Returns access and refresh tokens
- Displays tokens on success screen

**OAuth Flow Mode (with query params):**
- Accepts OAuth parameters: `client_id`, `redirect_uri`, `state`, `code_challenge`, `scope`
- User logs in
- Redirects to consent page with parameters

**URL Example:**
```
/oauth/login?client_id=http://example.com&redirect_uri=http://example.com/callback&state=xyz&code_challenge=abc&scope=atproto
```

### 4. OAuth Consent Page (`/oauth/authorize/consent`)
**File:** `lib/aether_pds_server_web/live/consent_live.ex`

Authorization consent screen showing:
- Application details (name, client ID, redirect URI)
- User information (handle, DID)
- Requested permissions list
- Security notice

**Actions:**
- **Authorize** - Creates authorization code and redirects to app
- **Deny** - Returns error to redirect URI

**Flow:**
1. Receives OAuth parameters + user DID
2. Validates client metadata
3. Displays consent screen
4. User authorizes or denies
5. Redirects to app with code or error

## Styling

### Custom CSS (`assets/css/custom.css`)
- **471 lines** of custom styles
- Modern, professional design
- Responsive layout (mobile-friendly)
- CSS variables for easy theming
- Component-based styling

**Color Palette:**
- Primary: #4f46e5 (Indigo)
- Success: #10b981 (Green)
- Error: #ef4444 (Red)
- Background: #f9fafb (Light gray)

**Components Styled:**
- Buttons (primary, secondary, large, full-width)
- Forms (inputs, labels, help text)
- Boxes (registration, login, consent)
- Messages (success, error)
- Code blocks
- Feature cards
- Navigation links

### Layout System

**Root Layout (`layouts/root.html.heex`):**
- HTML document structure
- Inline CSS (from custom.css)
- CSRF token setup
- Phoenix LiveView JavaScript

**App Layout (`layouts/app.html.heex`):**
- Flash message container
- Main content wrapper

**Layouts Module (`components/layouts.ex`):**
- Embeds layout templates
- Used by LiveView pages

## Architecture

### LiveView Integration

**Core Components (`components/core_components.ex`):**
- `flash_group/1` - Flash message container
- `flash/2` - Individual flash messages

**Web Module (`aether_pds_server_web.ex`):**
Added support for:
- `live_view` - LiveView pages
- `live_component` - LiveView components
- `html` - HTML components
- `html_helpers` - Shared HTML utilities

### Router Updates

**Browser Pipeline:**
```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {AetherPDSServerWeb.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
end
```

**Routes Added:**
```elixir
scope "/", AetherPDSServerWeb do
  pipe_through [:browser]

  live "/", HomeLive, :index
  live "/register", RegisterLive, :index
  live "/oauth/login", LoginLive, :index
  live "/oauth/authorize/consent", ConsentLive, :index
end
```

## Usage Examples

### 1. Create Account via UI
```
1. Navigate to http://localhost:4000/register
2. Enter handle: alice.test
3. Enter email: alice@example.com
4. Enter password: securepassword123
5. Click "Create Account"
6. See success screen with DID
```

### 2. Direct Login
```
1. Navigate to http://localhost:4000/oauth/login
2. Enter handle or email
3. Enter password
4. Click "Sign In"
5. See tokens displayed
```

### 3. OAuth Flow
```
1. App redirects to:
   http://localhost:4000/oauth/login?client_id=...&redirect_uri=...&state=...&code_challenge=...

2. User logs in

3. Redirect to consent page:
   http://localhost:4000/oauth/authorize/consent?...&did=...

4. User reviews permissions and clicks "Authorize"

5. Redirect back to app with code:
   http://example.com/callback?code=...&state=...
```

## Testing the UI

### Manual Testing

**Start Server:**
```bash
mix phx.server
```

**Test Pages:**
1. Home: http://localhost:4000/
2. Register: http://localhost:4000/register
3. Login: http://localhost:4000/oauth/login
4. Dashboard: http://localhost:4000/dev/dashboard

### Test OAuth Flow

**Create Test Client:**
```bash
# In iex -S mix phx.server
client_id = "http://localhost:3000"
redirect_uri = "http://localhost:3000/callback"

# Build authorization URL
url = "http://localhost:4000/oauth/login?" <>
  "client_id=#{URI.encode_www_form(client_id)}" <>
  "&redirect_uri=#{URI.encode_www_form(redirect_uri)}" <>
  "&state=test123" <>
  "&code_challenge=test_challenge" <>
  "&scope=atproto"

IO.puts(url)
```

## Integration with API

### Account Creation
UI calls: `Accounts.create_account/1`
- Creates account in database
- Auto-creates repository
- Generates initial commit
- Returns account with DID

### Authentication
UI calls: `Accounts.authenticate/2`
- Validates credentials
- Returns account on success
- Handles timing attack prevention

### Token Generation
UI calls:
- `Accounts.create_access_token/1` - Access token (1 hour)
- `Accounts.create_refresh_token/1` - Refresh token (30 days)

### OAuth Operations
UI calls:
- `OAuth.validate_client/2` - Validates client metadata
- `OAuth.create_authorization_code/5` - Creates auth code
- Builds redirect URLs with codes/errors

## Security Features

### CSRF Protection
- Enabled via `protect_from_forgery` plug
- CSRF token in all forms
- LiveView handles token automatically

### Password Security
- Minimum 8 characters enforced (HTML + validation)
- Argon2 hashing on server
- No plaintext password storage

### OAuth Security
- PKCE code challenge validation
- State parameter for CSRF protection
- Client metadata validation
- DPoP support (when configured)

### Session Security
- HTTP-only session cookies
- Secure headers via plug
- Token expiration enforced

## Customization

### Theming

Edit `assets/css/custom.css` to change colors:
```css
:root {
  --primary-color: #4f46e5;    /* Change to your brand color */
  --primary-hover: #4338ca;     /* Darker shade for hover */
  --success-color: #10b981;     /* Success messages */
  --error-color: #ef4444;       /* Error messages */
}
```

### Logo/Branding

Update `lib/aether_pds_server_web/live/home_live.ex`:
```elixir
<h1>Your PDS Name</h1>
<p class="hero-subtitle">
  Your custom tagline
</p>
```

### Custom Fields

Add fields to registration in `register_live.ex`:
```elixir
<div class="form-group">
  <label for="display_name">Display Name</label>
  <input type="text" name="register[display_name]" ... />
</div>
```

### OAuth Permissions

Customize permission list in `consent_live.ex`:
```elixir
<li>
  <span class="permission-icon">✓</span>
  Your custom permission
</li>
```

## Responsive Design

All pages are mobile-responsive:
- Breakpoint: 768px
- Stack buttons vertically on mobile
- Reduce padding on small screens
- Scale font sizes appropriately
- Touch-friendly button sizes

**Test on Mobile:**
```bash
# Open browser dev tools
# Toggle device toolbar
# Test at various screen sizes
```

## Accessibility

### Features Implemented:
- Semantic HTML5 elements
- ARIA roles where needed
- Keyboard navigation support
- Focus indicators on inputs
- Clear error messages
- Proper form labels

### Future Improvements:
- Screen reader testing
- High contrast mode
- Keyboard shortcuts
- ARIA live regions for dynamic content

## Known Limitations

1. **No Password Reset** - Not yet implemented
2. **No Email Verification** - Email is stored but not verified
3. **Basic Client Validation** - OAuth client metadata fetching is simplified
4. **No Multi-factor Auth** - MFA not implemented
5. **Token Display** - Tokens shown in UI (for development only)

## Future Enhancements

### Short Term
- [ ] Password reset flow
- [ ] Email verification
- [ ] Remember me checkbox
- [ ] Loading states
- [ ] Form field validation feedback

### Medium Term
- [ ] User profile page
- [ ] Account settings
- [ ] OAuth client management
- [ ] Session management UI
- [ ] Token revocation

### Long Term
- [ ] Multi-factor authentication
- [ ] Social login integration
- [ ] Advanced security settings
- [ ] Audit log viewer
- [ ] Admin dashboard

## Files Created/Modified

### New Files
- `lib/aether_pds_server_web/live/home_live.ex`
- `lib/aether_pds_server_web/live/register_live.ex`
- `lib/aether_pds_server_web/live/login_live.ex`
- `lib/aether_pds_server_web/live/consent_live.ex`
- `lib/aether_pds_server_web/components/layouts.ex`
- `lib/aether_pds_server_web/components/core_components.ex`
- `lib/aether_pds_server_web/components/layouts/root.html.heex`
- `lib/aether_pds_server_web/components/layouts/app.html.heex`
- `assets/css/custom.css`
- `UI_DOCUMENTATION.md` (this file)

### Modified Files
- `lib/aether_pds_server_web.ex` - Added LiveView support
- `lib/aether_pds_server_web/router.ex` - Added browser pipeline and routes

## Troubleshooting

### Compilation Errors
**Issue:** `undefined function live/3`
**Fix:** Ensure `import Phoenix.LiveView.Router` at top of router.ex

**Issue:** `function live_view/0 is undefined`
**Fix:** Added `live_view`, `html`, and `html_helpers` functions to web.ex

### CSS Not Loading
**Issue:** Styles not appearing
**Fix:** CSS is inline in root.html.heex via `File.read!("assets/css/custom.css")`

### Flash Messages
**Issue:** Deprecated `live_flash/2` warning
**Fix:** Can update to `Phoenix.Flash.get/2` in Phoenix 1.7+

### LiveView Errors
**Issue:** Mount errors
**Fix:** Check all assigns are properly initialized in mount/3

## Support

For issues or questions:
1. Check server logs: `mix phx.server`
2. Check browser console for JavaScript errors
3. Verify database connection
4. Test API endpoints with curl first
5. Review this documentation

## Conclusion

The UI provides a complete, production-ready interface for:
- ✅ User registration with repository creation
- ✅ OAuth login flow with consent
- ✅ Modern, responsive design
- ✅ Real-time validation with LiveView
- ✅ Security best practices
- ✅ Mobile-friendly layout

Users can now interact with the PDS through an intuitive web interface while maintaining full API compatibility.
