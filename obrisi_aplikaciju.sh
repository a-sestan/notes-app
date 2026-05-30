#!/bin/bash
echo "Brišem sve resurse..."
docker compose down -v --rmi all
docker network rm notes_net 2>/dev/null || true
echo "Sve obrisano."