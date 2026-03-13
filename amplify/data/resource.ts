import { type ClientSchema, a, defineData } from '@aws-amplify/backend';

const schema = a.schema({
  Expense: a
    .model({
      title: a.string(),
      amount: a.integer(),
      date: a.string(),
      category: a.string(),
      type: a.string(),
      shop: a.string(),
      memo: a.string(),
      receiptImagePath: a.string(),
    })
    .authorization((allow) => [allow.owner()]), // ← これを追加！
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: 'userPool',
  },
});