package ninjabrainbot.io;

import java.awt.Toolkit;
import java.awt.datatransfer.Clipboard;
import java.awt.datatransfer.DataFlavor;
import java.awt.datatransfer.UnsupportedFlavorException;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;

import ninjabrainbot.event.IObservable;
import ninjabrainbot.event.ObservableField;
import ninjabrainbot.io.preferences.NinjabrainBotPreferences;
import ninjabrainbot.util.Logger;

public class ClipboardReader implements IClipboardProvider, Runnable {

	private final NinjabrainBotPreferences preferences;

	final Clipboard clipboard;
	String lastClipboardString;

	private final AtomicBoolean forceReadLater;

	final ObservableField<String> clipboardString;

	public ClipboardReader(NinjabrainBotPreferences preferences) {
		this.preferences = preferences;
		clipboard = Toolkit.getDefaultToolkit().getSystemClipboard();
		clipboardString = new ObservableField<>(null, true);
		lastClipboardString = "";
		forceReadLater = new AtomicBoolean(false);
	}

	public IObservable<String> clipboardText() {
		return clipboardString;
	}

	public void forceRead() {
		forceReadLater.set(true);
	}

	@Override
	public void run() {
		String waylandDisplay = System.getenv("WAYLAND_DISPLAY");
		if (waylandDisplay != null && !waylandDisplay.isEmpty()) {
			try {
				String[] command = { "wl-paste", "--watch", "sh", "-c", "cat; echo" };
				Process wlPaste = Runtime.getRuntime().exec(command);
				Runtime.getRuntime().addShutdownHook(new Thread(() -> wlPaste.destroy()));
				Logger.log("Reading the clipboard through wl-paste.");

				BufferedReader reader = new BufferedReader(new InputStreamReader(wlPaste.getInputStream(), StandardCharsets.UTF_8));
				String line = reader.readLine();
				while (line != null) {
					if (line.length() > 1000)
						line = line.substring(0, 1000);
					if (!line.isEmpty() && !lastClipboardString.equals(line)) {
						onClipboardUpdated(line);
						lastClipboardString = line;
					}
					line = reader.readLine();
				}
				reader.close();
				Logger.log("wl-paste stopped, falling back to polling the clipboard.");
			} catch (IOException e) {
				Logger.log("Could not read the clipboard through wl-paste, falling back to polling the clipboard.");
			}
		}

		while (true) {
			boolean read = !preferences.altClipboardReader.get();
			if (preferences.altClipboardReader.get() && forceReadLater.get()) {
				read = true;
				// Sleep 0.1 seconds to let the game update the clipboard
				try {
					Thread.sleep(100);
				} catch (InterruptedException e) {
					e.printStackTrace();
				}
			}
			String clipboardString = null;
			try {
				if (read) {
					clipboardString = ((String) clipboard.getData(DataFlavor.stringFlavor));
					if (clipboardString.length() > 1000)
						clipboardString = clipboardString.substring(0, 1000);
				}
			} catch (UnsupportedFlavorException | IllegalStateException | IOException ignored) {
			}
			if (clipboardString != null && !lastClipboardString.equals(clipboardString)) {
				onClipboardUpdated(clipboardString);
				lastClipboardString = clipboardString;
			}
			// Sleep 0.1 seconds
			try {
				Thread.sleep(100);
			} catch (InterruptedException e) {
				e.printStackTrace();
			}
		}
	}

	private void onClipboardUpdated(String clipboard) {
		clipboardString.set(clipboard);
	}

}
