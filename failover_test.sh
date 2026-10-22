#!/usr/bin/env bash
# Fault-tolerance test: terminate one web instance and watch the site through the ALB.
# Usage: ./failover_test.sh <stack-name> [region]
set -euo pipefail

STACK="${1:?usage: $0 <stack-name> [region]}"
REGION="${2:-${AWS_REGION:-us-east-1}}"
ASG="${STACK}-asg"

URL=$(aws cloudformation describe-stacks --region "$REGION" --stack-name "$STACK" \
  --query "Stacks[0].Outputs[?OutputKey=='SiteURL'].OutputValue" --output text)

echo "Site: $URL"
echo "Instances before test:"
aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" \
  --query "AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,HealthStatus]" --output table

VICTIM=$(aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" \
  --query "AutoScalingGroups[0].Instances[0].InstanceId" --output text)

echo "Terminating $VICTIM at $(date +%T) ..."
aws ec2 terminate-instances --region "$REGION" --instance-ids "$VICTIM" >/dev/null

ok=0
fail=0
for i in $(seq 1 120); do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$URL/health" || true)
  who=$(curl -s --max-time 3 "$URL/whoami" || true)
  if [ "$code" = "200" ]; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
  echo "$(date +%T)  HTTP $code  $who"
  sleep 1
done

echo
echo "Requests OK: $ok   Failed: $fail"
echo "Instances after test (the ASG should be replacing the terminated one):"
aws autoscaling describe-auto-scaling-groups --region "$REGION" --auto-scaling-group-names "$ASG" \
  --query "AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,LifecycleState,HealthStatus]" --output table
