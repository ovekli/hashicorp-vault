#!/bin/bash

echo "Install helm chart"
helm upgrade --install vault helm-chart -f helm-chart/values.yaml