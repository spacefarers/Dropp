export type FileDoc = {
  _id?: string;
  user_id: string;
  name: string;
  url: string;
  size: number;
  content_type?: string;
  created_at: string;
  status?: 'pending' | 'complete';
};
