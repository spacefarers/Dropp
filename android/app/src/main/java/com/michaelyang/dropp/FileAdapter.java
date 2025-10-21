package com.michaelyang.dropp;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

import java.util.List;
import java.util.Locale;

public class FileAdapter extends RecyclerView.Adapter<FileAdapter.FileViewHolder> {

    private final List<File> files;
    private final OnFileClickListener listener;

    public interface OnFileClickListener {
        void onDownloadClick(File file);
        void onDeleteClick(File file);
    }

    public FileAdapter(List<File> files, OnFileClickListener listener) {
        this.files = files;
        this.listener = listener;
    }

    @NonNull
    @Override
    public FileViewHolder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext()).inflate(R.layout.list_item_file, parent, false);
        return new FileViewHolder(view);
    }

    @Override
    public void onBindViewHolder(@NonNull FileViewHolder holder, int position) {
        File file = files.get(position);
        holder.bind(file, listener);
    }

    @Override
    public int getItemCount() {
        return files.size();
    }

    static class FileViewHolder extends RecyclerView.ViewHolder {

        private final TextView fileName;
        private final TextView fileSize;
        private final ImageButton downloadButton;
        private final ImageButton deleteButton;

        public FileViewHolder(@NonNull View itemView) {
            super(itemView);
            fileName = itemView.findViewById(R.id.file_name);
            fileSize = itemView.findViewById(R.id.file_size);
            downloadButton = itemView.findViewById(R.id.download_button);
            deleteButton = itemView.findViewById(R.id.delete_button);
        }

        public void bind(final File file, final OnFileClickListener listener) {
            fileName.setText(file.getName());
            fileSize.setText(formatFileSize(file.getSize()));
            downloadButton.setOnClickListener(v -> listener.onDownloadClick(file));
            deleteButton.setOnClickListener(v -> listener.onDeleteClick(file));
        }

        private String formatFileSize(long size) {
            if (size < 1024) {
                return String.format(Locale.getDefault(), "%d B", size);
            } else if (size < 1024 * 1024) {
                return String.format(Locale.getDefault(), "%.2f KB", (float) size / 1024);
            } else if (size < 1024 * 1024 * 1024) {
                return String.format(Locale.getDefault(), "%.2f MB", (float) size / (1024 * 1024));
            } else {
                return String.format(Locale.getDefault(), "%.2f GB", (float) size / (1024 * 1024 * 1024));
            }
        }
    }
}
