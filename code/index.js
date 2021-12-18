const AWS = require("aws-sdk");
const iam = new AWS.IAM();
const sns = new AWS.SNS();
const async = require("async");

exports.handler = async (event, context) => {
  let keyResults, keyData, lastUsedResults;
  let keyArray = [];
  let oldKeyArray = [];

  let userResults = await iam.listUsers({}).promise();
  let userData = userResults.Users.map(user => { return { UserName: user.UserName }; });
  // console.log(userData);

  for (userItem of userData) {
    keyResults = await iam.listAccessKeys(userItem).promise();
    keyData = keyResults.AccessKeyMetadata.filter(value => { return value.Status === "Active"});
    keyData = keyData.map(key => { return { UserName: key.UserName, AccessKeyId: key.AccessKeyId, CreateDate: key.CreateDate }; });
    keyArray = keyArray.concat(keyData);
  }

  for (keyItem of keyArray) {
    createTime = new Date(keyItem.CreateDate).getTime();
    month = 60*60*24*180;
    timeSince = Date.now() - createTime;
    if (timeSince > month) {
      oldKeyArray = oldKeyArray.concat(keyItem);
    }
  }

  if(oldKeyArray.length > 0) {
    let msg = {
      data: "keys older than 180 days",
      keyData: oldKeyArray
    }
    let params = {
      Message: JSON.stringify(msg),
      TopicArn: process.env.TOPIC_ARN
    }
    let publishTextPromise = await sns.publish(params).promise();
    console.log(oldKeyArray);
  }
}

