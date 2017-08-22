# Autoscaling Rolling Update

Will perform an update of an autoscaling group to the latest launch configuration. Respects the min and the max for an autoscaling group and simply removes instances that have an older launch configuration applied letting them be replaced one by one.

## Usage

```
docker run coldog/autoscaling-rolling-update [autoscaling-group]
```
