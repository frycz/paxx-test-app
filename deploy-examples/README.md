# Deployment Examples

This directory contains example deployment configurations that can be added to your project.

## Usage

```bash
paxx deploy add <deployment-name>
```

For example:
```bash
paxx deploy add linux-server
```

This copies the deployment files to `deploy/<deployment-name>/` and sets up any required configurations.

## Available Deployments

- **linux-server** - Deploy to any Linux server with zero-downtime blue-green deployments

## Optional Directory

This directory is optional and can be safely removed if you use custom deployment configurations or don't need the provided examples.
