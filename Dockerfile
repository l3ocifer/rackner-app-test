# Use the official Nginx image as the base image
FROM --platform=linux/amd64 nginx:1.24.0

# Create a custom HTML file with the "Hello Rackner" message
RUN echo '<!DOCTYPE html><html><head><title>Hello Rackner</title></head><body><h1>Hello Rackner</h1></body></html>' > /usr/share/nginx/html/index.html
