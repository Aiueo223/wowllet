import { defineStorage } from '@aws-amplify/backend';

export const storage = defineStorage({
  name: 'wowlletDrive',
  access: (allow) => ({
    // 誰でもレシート画像をアップロード・読み込みできるようにする仮設定
    'receipts/*': [
      allow.guest.to(['read', 'write', 'delete'])
    ]
  })
});