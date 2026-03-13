import { defineBackend } from '@aws-amplify/backend';
import { auth } from './auth/resource';
import { data } from './data/resource';
import { storage } from './storage/resource'; // ←追加：倉庫の設計図を読み込む

defineBackend({
  auth,
  data,
  storage, // ←追加：バックエンド本体に倉庫を登録する
});