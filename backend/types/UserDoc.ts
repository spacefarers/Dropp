export type UserDoc = {
  _id: string;
  cap: number; // storage limit in bytes
  used: number; // current usage in bytes
  created_at?: string;
  email?: string;
};
