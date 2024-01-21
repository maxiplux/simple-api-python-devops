#!/bin/bash

SERVICE_ARN="arn:aws:apprunner:region:account:service/maxiplux-python-2024"

if aws apprunner describe-service --service-arn $SERVICE_ARN > /dev/null 2>&1; then
    echo "Service exists, updating..."
    aws apprunner update-service --service-arn $SERVICE_ARN --cli-input-json file://update-service.json
else
    echo "Service does not exist, creating..."
    aws apprunner create-service --cli-input-json file://create-service.json
fi
