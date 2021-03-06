#!/bin/bash
###############################################################################
# scale_in_<AutoScalingグループ種別>_autosacle.sh
# AutoScalingグループ設定更新(起動設定差し替え、ScaleIn)スクリプト
# 引数1： AutoScalingグループの名前
# 引数2: ELBの名前
#
###############################################################################

## 変数
asg_name=$1
elb=$2

## 引数確認
target_asg=`aws autoscaling describe-auto-scaling-groups \
--query 'AutoScalingGroups[].AutoScalingGroupName' \
--output text \
| grep -w $asg_name`

if [[ $target_asg = "$null" ]]; then
  echo "【ERROR】AutoScalingグループが存在していません"
  exit 1
fi

## 更新前のAutoScalingグループサイズ
before_min_size=`aws autoscaling describe-auto-scaling-groups \
--auto-scaling-group-names $asg_name \
--query 'AutoScalingGroups[].MinSize' \
--output text`

before_max_size=`aws autoscaling describe-auto-scaling-groups \
--auto-scaling-group-names $asg_name \
--query 'AutoScalingGroups[].MaxSize' \
--output text`

before_desired_size=`aws autoscaling describe-auto-scaling-groups \
--auto-scaling-group-names $asg_name \
--query 'AutoScalingGroups[].DesiredCapacity' \
--output text`

## 更新後のAutoScalingグループサイズ
## 更新前の半分の数に設定する
after_min_size=$((before_min_size / 2))
after_max_size=$((before_max_size / 2))
after_desired_size=$((before_desired_size / 2))

## AutoScalingグループ更新
aws autoscaling update-auto-scaling-group \
--auto-scaling-group-name $asg_name \
--min-size $after_min_size \
--max-size $after_max_size \
--desired-capacity $after_desired_size

Stat=$?
if [ $Stat = 0 ]; then
  echo "【INFO】インスタンス停止中の為、120秒間待機します"
  sleep 120
else
  echo "【ERROR】AutoScalingグループの更新に失敗しました"
  exit 1
fi

## ELBヘルスチェック確認
healthcheck()
{
elb_healthcheck=`aws elb describe-instance-health \
--load-balancer-name $elb \
--query 'InstanceStates[].State' \
|grep -c InService`

echo $elb_healthcheck
}

i=0
while [ $i -lt 12 ]
do
  check_inservice=`healthcheck`

  if [[ $check_inservice = $after_desired_size ]]; then
    echo "【INFO】AutoScalingグループの更新が完了しました($asg_name)"
    break
  else
    echo "【INFO】インスタンス数が希望数になるまで待機します"
    sleep 30
    i=$((i + 1))
  fi
done

instances()
{
elb_instances=`aws elb describe-instance-health \
--load-balancer-name $elb \
--query 'InstanceStates[].InstanceId' \
--output text`

echo $elb_instances
}

if [[ $check_inservice = $after_desired_size ]]; then
  echo "【INFO】対象インスタンス：`instances`"
  echo "【INFO】AutoScalingグループの更新が完了しました($asg_name)"
else
  echo "【ERROR】インスタンスをELBから切り離せませんでした"
  exit 1
fi
