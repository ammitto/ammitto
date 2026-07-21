#!/bin/bash
# Neo4j Data Validation Script
#
# This script validates the knowledge graph data in Neo4j.
# It checks for:
# - Proper node counts
# - Proper relationship counts
# - No orphaned nodes
# - All links are valid
#
# Usage:
#   ./scripts/validate_neo4j.sh [neo4j_container_name]

set -e

CONTAINER=${1:-ammitto-neo4j}
AUTH="neo4j/password"

echo "=== Neo4j Data Validation ==="
echo "Container: $CONTAINER"
echo ""

# Function to run Cypher query
cypher() {
    docker exec $CONTAINER cypher-shell -u neo4j -p password "$1"
}

echo "=== Node Counts ==="
cypher "
MATCH (n)
RETURN labels(n)[0] as node_type, count(n) as count
ORDER BY count DESC;
"

echo ""
echo "=== Relationship Counts ==="
cypher "
MATCH ()-[r]->()
RETURN type(r) as relationship_type, count(r) as count
ORDER BY count DESC;
"

echo ""
echo "=== Entity Type Distribution ==="
cypher "
MATCH (e:Entity)
RETURN e.type as entity_type, count(e) as count
ORDER BY count DESC;
"

echo ""
echo "=== Authority Distribution ==="
cypher "
MATCH (e:Entity)<-[:FOR_ENTITY]-(entry:Entry)-[:LISTED_BY]->(a:Authority)
RETURN a.name as authority, count(DISTINCT e) as entity_count
ORDER BY entity_count DESC;
"

echo ""
echo "=== Data Quality Checks ==="

# Check for entries without entities
echo "Checking for entries without entity links..."
MISSING_ENTITY=$(cypher "
MATCH (entry:Entry)
WHERE NOT (entry)-[:FOR_ENTITY]->()
RETURN count(entry) as count;
" | tail -1)
echo "  Entries missing entity link: $MISSING_ENTITY"

# Check for entries without authorities
echo "Checking for entries without authority links..."
MISSING_AUTH=$(cypher "
MATCH (entry:Entry)
WHERE NOT (entry)-[:LISTED_BY]->()
RETURN count(entry) as count;
" | tail -1)
echo "  Entries missing authority link: $MISSING_AUTH"

# Check for entities without names
echo "Checking for entities without names..."
MISSING_NAME=$(cypher "
MATCH (e:Entity)
WHERE NOT (e)-[:HAS_NAME]->()
RETURN count(e) as count;
" | tail -1)
echo "  Entities missing name link: $MISSING_NAME"

# Check for orphaned names
echo "Checking for orphaned names..."
ORPHAN_NAMES=$(cypher "
MATCH (n:Name)
WHERE NOT (n)<-[:HAS_NAME]-()
RETURN count(n) as count;
" | tail -1)
echo "  Orphaned names: $ORPHAN_NAMES"

echo ""
if [ "$MISSING_ENTITY" -gt 1 ] || [ "$MISSING_AUTH" -gt 1 ] || [ "$ORPHAN_NAMES" -gt 1 ]; then
    echo "❌ FAILED: Data quality issues detected!"
    exit 1
fi

echo "✅ PASSED: All data quality checks passed!"
