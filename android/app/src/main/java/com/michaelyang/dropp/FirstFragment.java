package com.michaelyang.dropp;

import android.app.DownloadManager;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.fragment.app.Fragment;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;

import com.michaelyang.dropp.databinding.FragmentFirstBinding;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

public class FirstFragment extends Fragment implements FileAdapter.OnFileClickListener {

    private static final String TAG = "FirstFragment";
    private FragmentFirstBinding binding;
    private SessionManager sessionManager;
    private OkHttpClient client;
    private FileAdapter adapter;
    private final List<File> files = new ArrayList<>();

    @Override
    public View onCreateView(
            @NonNull LayoutInflater inflater, ViewGroup container,
            Bundle savedInstanceState
    ) {
        binding = FragmentFirstBinding.inflate(inflater, container, false);
        return binding.getRoot();
    }

    public void onViewCreated(@NonNull View view, Bundle savedInstanceState) {
        super.onViewCreated(view, savedInstanceState);

        Log.d(TAG, "onViewCreated: Initializing FirstFragment");
        sessionManager = new SessionManager(requireContext());
        client = HttpClient.getInstance();

        adapter = new FileAdapter(files, this);
        binding.recyclerView.setAdapter(adapter);

        binding.swipeRefreshLayout.setOnRefreshListener(this::fetchFiles);

        Log.d(TAG, "onViewCreated: Calling fetchFiles()");
        fetchFiles();
    }

    private void fetchFiles() {
        Log.d(TAG, "fetchFiles: Starting file fetch");
        binding.swipeRefreshLayout.setRefreshing(true);

        String token = sessionManager.getToken();
        Log.d(TAG, "fetchFiles: Token exists: " + (token != null && !token.isEmpty()));

        if (token == null || token.isEmpty()) {
            Log.e(TAG, "fetchFiles: No token available");
            Toast.makeText(getContext(), "Not logged in", Toast.LENGTH_SHORT).show();
            binding.swipeRefreshLayout.setRefreshing(false);
            return;
        }

        Request request = new Request.Builder()
                .url("https://dropp.yangm.tech/api/list")
                .addHeader("Authorization", "Bearer " + token)
                .build();

        Log.d(TAG, "fetchFiles: Enqueuing request to " + request.url());
        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                Log.e(TAG, "fetchFiles: Network request failed", e);
                if (getActivity() != null) {
                    getActivity().runOnUiThread(() -> {
                        Toast.makeText(getContext(), "Failed to fetch files: " + e.getMessage(), Toast.LENGTH_SHORT).show();
                        binding.swipeRefreshLayout.setRefreshing(false);
                    });
                }
            }

            @Override
            public void onResponse(@NonNull Call call, @NonNull Response response) throws IOException {
                Log.d(TAG, "fetchFiles: Received response, code: " + response.code());
                if (getActivity() != null) {
                    if (response.isSuccessful()) {
                        final String responseBody = response.body().string();
                        Log.d(TAG, "fetchFiles: Response body: " + responseBody);
                        getActivity().runOnUiThread(() -> {
                            try {
                                files.clear();
                                JSONObject jsonResponse = new JSONObject(responseBody);
                                JSONArray jsonArray = jsonResponse.getJSONArray("files");
                                Log.d(TAG, "fetchFiles: Parsed " + jsonArray.length() + " files");
                                for (int i = 0; i < jsonArray.length(); i++) {
                                    JSONObject jsonObject = jsonArray.getJSONObject(i);
                                    String id = jsonObject.getString("_id");
                                    String name = jsonObject.getString("name");
                                    long size = jsonObject.getLong("size");
                                    String blobUrl = jsonObject.getString("download_url");
                                    files.add(new File(id, name, size, blobUrl));
                                    Log.d(TAG, "fetchFiles: Added file: " + name + " (" + size + " bytes)");
                                }
                                adapter.notifyDataSetChanged();
                                updateEmptyView();
                                Log.d(TAG, "fetchFiles: Adapter notified, total files: " + files.size());
                            } catch (JSONException e) {
                                Log.e(TAG, "fetchFiles: JSON parsing error", e);
                                Toast.makeText(getContext(), "Failed to parse files", Toast.LENGTH_SHORT).show();
                            }
                            binding.swipeRefreshLayout.setRefreshing(false);
                        });
                    } else {
                        Log.e(TAG, "fetchFiles: Unsuccessful response: " + response.code());
                        getActivity().runOnUiThread(() -> {
                            Toast.makeText(getContext(), "Failed to fetch files: HTTP " + response.code(), Toast.LENGTH_SHORT).show();
                            binding.swipeRefreshLayout.setRefreshing(false);
                        });
                    }
                }
            }
        });
    }

    private void updateEmptyView() {
        if (files.isEmpty()) {
            binding.recyclerView.setVisibility(View.GONE);
            binding.emptyView.setVisibility(View.VISIBLE);
            binding.emptyViewIcon.setVisibility(View.VISIBLE);
        } else {
            binding.recyclerView.setVisibility(View.VISIBLE);
            binding.emptyView.setVisibility(View.GONE);
            binding.emptyViewIcon.setVisibility(View.GONE);
        }
    }

    @Override
    public void onDestroyView() {
        super.onDestroyView();
        binding = null;
    }

    @Override
    public void onDownloadClick(File file) {
        Toast.makeText(getContext(), "Downloading " + file.getName(), Toast.LENGTH_SHORT).show();

        Request request = new Request.Builder()
                .url(file.getBlobUrl())
                .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                Log.e(TAG, "onDownloadClick: Download failed", e);
                if (getActivity() != null) {
                    getActivity().runOnUiThread(() ->
                        Toast.makeText(getContext(), "Download failed: " + e.getMessage(), Toast.LENGTH_SHORT).show()
                    );
                }
            }

            @Override
            public void onResponse(@NonNull Call call, @NonNull Response response) throws IOException {
                if (getActivity() != null) {
                    if (response.isSuccessful() && response.body() != null) {
                        try {
                            saveFile(response.body().bytes(), file.getName());
                            getActivity().runOnUiThread(() ->
                                Toast.makeText(getContext(), "Downloaded " + file.getName(), Toast.LENGTH_SHORT).show()
                            );
                        } catch (IOException e) {
                            Log.e(TAG, "onDownloadClick: Failed to save file", e);
                            getActivity().runOnUiThread(() ->
                                Toast.makeText(getContext(), "Failed to save file", Toast.LENGTH_SHORT).show()
                            );
                        }
                    } else {
                        Log.e(TAG, "onDownloadClick: Unsuccessful response: " + response.code());
                        getActivity().runOnUiThread(() ->
                            Toast.makeText(getContext(), "Download failed: HTTP " + response.code(), Toast.LENGTH_SHORT).show()
                        );
                    }
                }
            }
        });
    }

    private void saveFile(byte[] fileBytes, String fileName) throws IOException {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Use MediaStore for Android 10+
            ContentResolver resolver = requireContext().getContentResolver();
            ContentValues contentValues = new ContentValues();
            contentValues.put(MediaStore.MediaColumns.DISPLAY_NAME, fileName);
            contentValues.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);

            Uri uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues);
            if (uri != null) {
                try (OutputStream outputStream = resolver.openOutputStream(uri)) {
                    if (outputStream != null) {
                        outputStream.write(fileBytes);
                        outputStream.flush();
                    }
                }
            }
        } else {
            // Use DownloadManager for older versions
            // This is a fallback - for pre-Q devices, we'll use a simpler approach
            // Note: You might need WRITE_EXTERNAL_STORAGE permission for this
            throw new IOException("Download not supported on this Android version");
        }
    }

    @Override
    public void onDeleteClick(File file) {
        Request request = new Request.Builder()
                .url("https://dropp.yangm.tech/api/files/" + file.getId())
                .addHeader("Authorization", "Bearer " + sessionManager.getToken())
                .delete()
                .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onFailure(@NonNull Call call, @NonNull IOException e) {
                if (getActivity() != null) {
                    getActivity().runOnUiThread(() -> Toast.makeText(getContext(), "Failed to delete file", Toast.LENGTH_SHORT).show());
                }
            }

            @Override
            public void onResponse(@NonNull Call call, @NonNull Response response) {
                if (getActivity() != null) {
                    getActivity().runOnUiThread(() -> {
                        if (response.isSuccessful()) {
                            Toast.makeText(getContext(), "File deleted", Toast.LENGTH_SHORT).show();
                            fetchFiles();
                        } else {
                            Toast.makeText(getContext(), "Failed to delete file", Toast.LENGTH_SHORT).show();
                        }
                    });
                }
            }
        });
    }
}
