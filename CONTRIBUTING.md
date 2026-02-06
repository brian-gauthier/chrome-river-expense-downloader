# Contributing to Chrome River Expense Downloader

Thank you for your interest in contributing! This document provides guidelines for contributing to this project.

## How to Contribute

### Reporting Bugs

If you find a bug, please open an issue with:
- A clear, descriptive title
- Steps to reproduce the issue
- Expected behavior
- Actual behavior
- Your environment (PowerShell version, Windows version, Chrome River API version)
- Any relevant error messages or logs (remove sensitive information!)

### Suggesting Enhancements

Enhancement suggestions are welcome! Please open an issue with:
- A clear description of the enhancement
- Why this enhancement would be useful
- Examples of how it would work

### Pull Requests

1. **Fork the repository** and create your branch from `main`
2. **Make your changes**
   - Follow the existing code style
   - Add comments for complex logic
   - Test your changes thoroughly
3. **Update documentation** if needed
   - Update README.md if you change functionality
   - Add inline comments for complex code
4. **Commit your changes**
   - Use clear, descriptive commit messages
   - Reference any related issues
5. **Submit a pull request**
   - Provide a clear description of the changes
   - Link to any related issues

## Development Guidelines

### Code Style

- Use clear, descriptive variable names
- Follow PowerShell naming conventions (Verb-Noun for functions)
- Add comments for complex logic
- Keep functions focused and single-purpose
- Use proper error handling with try/catch blocks

### Testing

Before submitting a pull request:
- Test with PowerShell 5.1 (the minimum supported version)
- Test with your Chrome River API credentials (if applicable)
- Verify no sensitive information is exposed in logs or output
- Check that error handling works as expected

### Security

**CRITICAL**: Never commit sensitive information:
- API keys, tokens, or credentials
- Company-specific configuration
- Personal information or file paths
- Actual expense data or PDFs

Always use:
- Placeholder values in examples
- Generic paths in documentation
- The provided template files as examples

### Documentation

- Update README.md for user-facing changes
- Update code comments for implementation changes
- Add examples for new features
- Keep documentation clear and concise

## Project Structure

```
chrome-river-expense-downloader/
├── .github/              # GitHub-specific files (optional)
├── docs/                 # Additional documentation
├── examples/             # Configuration templates and examples
├── scripts/              # PowerShell scripts
├── .gitignore           # Git ignore rules
├── CONTRIBUTING.md      # This file
├── LICENSE              # MIT License
└── README.md            # Main documentation
```

## Questions?

If you have questions about contributing, feel free to:
- Open an issue with the "question" label
- Start a discussion in the Discussions tab (if enabled)

## Code of Conduct

### Our Standards

- Be respectful and inclusive
- Focus on constructive feedback
- Accept constructive criticism gracefully
- Prioritize the community's best interests

### Unacceptable Behavior

- Harassment, discrimination, or offensive comments
- Publishing others' private information
- Trolling or insulting/derogatory comments
- Any conduct inappropriate in a professional setting

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

## Recognition

Contributors will be recognized in:
- Git commit history
- Release notes (for significant contributions)
- A CONTRIBUTORS.md file (if created)

Thank you for contributing! 🚀
