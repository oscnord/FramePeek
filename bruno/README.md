# FramePeek API - Bruno Collection

[Bruno](https://www.usebruno.com/) collection for testing the FramePeek REST API.

## Setup

1. Install Bruno from https://www.usebruno.com/
2. Open Bruno and click "Open Collection"
3. Navigate to this `bruno/FramePeek` folder

## Prerequisites

- FramePeek app must be running
- Server must be started (click "Server" in sidebar, then "Start Server")
- Default server URL: `http://127.0.0.1:8080`

## Quick Start

1. Run **Health Check** to verify the server is running
2. Edit **Analyze File by Path** and update the `path` to a real video file
3. Run the request - note the `id` in the response
4. Run **Get Job Status** with that `id` to check progress/get results
