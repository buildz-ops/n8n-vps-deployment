# Contributing to n8n VPS Deployment

Thank you for your interest in contributing to this project! This guide will help you get started.

## 📋 Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)
- [Documentation](#documentation)
- [Testing](#testing)

## Code of Conduct

This project adheres to a simple code of conduct:

- Be respectful and constructive
- Focus on what is best for the community
- Show empathy towards other community members
- Accept constructive criticism gracefully

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

When reporting bugs, include:

- **Clear title and description**
- **Steps to reproduce** the problem
- **Expected behavior** vs actual behavior
- **Environment details**:
  - OS version (e.g., Ubuntu 22.04)
  - Docker version
  - n8n version
  - Browser (if UI-related)
- **Logs and error messages** (use code blocks)
- **Screenshots** if applicable

### Suggesting Enhancements

Enhancement suggestions are welcome! Please include:

- **Use case**: Why is this enhancement needed?
- **Proposed solution**: How should it work?
- **Alternatives considered**: What other approaches did you think about?
- **Impact**: Who benefits from this change?

### Contributing Code

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Make your changes**
4. **Test thoroughly**
5. **Commit your changes**: `git commit -m 'Add amazing feature'`
6. **Push to the branch**: `git push origin feature/amazing-feature`
7. **Open a Pull Request**

### Contributing Documentation

Documentation improvements are highly valued:

- Fix typos and grammatical errors
- Improve clarity and readability
- Add missing information
- Update outdated content
- Add examples and use cases

## Development Setup

### Prerequisites

- Ubuntu 22.04+ (or compatible Linux distribution)
- Docker 20.10+
- Docker Compose v2.0+
- Git
- Text editor (VS Code, vim, nano, etc.)

### Local Testing Environment

1. **Clone your fork**:
   ```bash
   git clone https://github.com/YOUR_USERNAME/n8n-vps-deployment.git
   cd n8n-vps-deployment
   ```

2. **Set up environment**:
   ```bash
   cp .env.example .env
   # Edit .env with test values
   ```

3. **Test deployment**:
   ```bash
   # Use a test domain or local setup
   docker compose up -d
   docker compose ps
   docker compose logs
   ```

4. **Make changes and test**:
   ```bash
   # Edit files
   docker compose down
   docker compose up -d
   # Verify changes work
   ```

### Testing Checklist

Before submitting a PR, verify:

- [ ] All containers start successfully
- [ ] Health checks pass
- [ ] SSL certificates are obtained (if applicable)
- [ ] Database connectivity works
- [ ] Redis queue mode functions
- [ ] Backup scripts execute without errors
- [ ] Health check script runs successfully
- [ ] No sensitive data in commits
- [ ] Documentation is updated

## Pull Request Process

### Before Submitting

1. **Update documentation** if you've changed functionality
2. **Test your changes** thoroughly
3. **Remove sensitive data** (IPs, passwords, domains)
4. **Use placeholders** for examples (e.g., `YOUR_DOMAIN.com`)
5. **Follow coding standards** (see below)
6. **Squash commits** if you have many small commits

### PR Template

When opening a PR, please include:

```markdown
## Description
Brief description of what this PR does.

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update

## How Has This Been Tested?
Describe the tests you ran and your test configuration.

## Checklist
- [ ] My code follows the project's coding standards
- [ ] I have updated the documentation accordingly
- [ ] I have tested this thoroughly
- [ ] I have removed all sensitive information
- [ ] My commits are clean and descriptive
```

### Review Process

1. Maintainers will review your PR
2. Feedback may be provided - please address comments
3. Once approved, your PR will be merged
4. Your contribution will be credited

## Coding Standards

### Shell Scripts

- Use `#!/bin/bash` shebang
- Include descriptive comments
- Use `set -e` for error handling
- Validate inputs
- Provide clear error messages
- Use meaningful variable names

Example:
```bash
#!/bin/bash
# ===========================================
# Script Description
# ===========================================

set -e

# Configuration
BACKUP_DIR="/opt/n8n/backups"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Function example
function backup_database() {
    echo "[$(date)] Starting backup..."
    # Implementation
}
```

### Docker Compose

- Use version "3.9"
- Include descriptive comments
- Organize by service type
- Use environment variables
- Set resource limits
- Configure health checks

### YAML Files

- 2-space indentation
- No tabs
- Include inline comments for non-obvious settings
- Group related settings together

### Markdown Documentation

- Use clear headers (H1 for title, H2 for sections)
- Include table of contents for long documents
- Use code blocks with language specification
- Add emoji sparingly for visual organization
- Keep line length reasonable (~100 chars)
- Use tables for structured data
- Include examples

## Documentation

### What to Document

- **Configuration changes**: Explain new settings
- **New features**: How to use them
- **Breaking changes**: Migration guide
- **Troubleshooting**: Common issues and solutions
- **Examples**: Real-world use cases

### Documentation Style

- **Be clear and concise**
- **Use active voice**
- **Provide examples**
- **Include verification steps**
- **Explain the "why"**, not just the "how"

### Placeholder Guidelines

Always use placeholders, never real data:

| Type | Placeholder | Never Use |
|------|-------------|-----------|
| IP Address | `YOUR_VPS_IP` or `203.0.113.10` | Real IPs |
| Domain | `n8n.YOUR_DOMAIN.com` or `n8n.example.com` | Real domains |
| Email | `your.email@example.com` | Real emails |
| Password | `YOUR_SECURE_PASSWORD_HERE` | Real passwords |
| Encryption Key | `YOUR_32_CHARACTER_KEY_HERE` | Real keys |

## Testing

### Manual Testing

1. **Fresh installation**: Test on clean Ubuntu system
2. **Upgrade path**: Test updates from previous versions
3. **Backup/restore**: Verify backup procedures work
4. **SSL certificates**: Test certificate acquisition
5. **Different environments**: Test on various VPS providers

### Automated Testing

While we don't have CI/CD yet, consider:

- Script syntax validation: `shellcheck script.sh`
- YAML validation: `yamllint docker-compose.yml`
- Markdown linting: `markdownlint *.md`

### Security Testing

- Check for exposed secrets
- Verify firewall rules
- Test SSH hardening
- Validate SSL/TLS configuration
- Review file permissions

## Commit Messages

### Format

```
type(scope): brief description

Detailed explanation if needed.

Fixes #123
```

### Types

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

### Examples

```
feat(backup): add retention policy for backups

Added configurable retention days for automatic cleanup
of old backup files.

Fixes #45
```

```
docs(readme): update SSL certificate troubleshooting

Added section about N8N_HOST configuration mismatch
causing certificate acquisition failures.
```

## Getting Help

If you need help with contributing:

1. Check existing issues and PRs
2. Review this CONTRIBUTING guide
3. Read the [README.md](README.md)
4. Open a discussion or issue

## Recognition

Contributors will be recognized in:

- GitHub contributors list
- Release notes (for significant contributions)
- README acknowledgments section

Thank you for contributing! 🙏
