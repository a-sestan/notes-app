#!/bin/bash
echo "Pripremam aplikaciju..."
docker network create notes_net 2>/dev/null || true
docker volume create db_data 2>/dev/null || true
docker compose build
echo "Aplikacija pripremljena!"