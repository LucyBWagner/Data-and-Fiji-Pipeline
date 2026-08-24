// =================================================================================
// Fiji ImageJ Macro: ALL CELLS BATCH MEASUREMENT (C1 + C2 + C3, lebend UND tot)
// AUSGABE PRO ORDNER:
//   <FolderName>_AllCells.csv mit Spalten:
//   Cell_ID | Area | C1_Mean | C2_Mean | C3_PI_Mean | Ratio_C1_C2 | Status
//
// Tot/lebend wird NICHT ueber eine Schwellwert-Maske im C3-Bild bestimmt,
// sondern nachtraeglich ueber die gemessene PI-Rohintensitaet (C3_PI_Mean).
//
// =================================================================================

// ==========================================
// --- 1. DEINE PERSÖNLICHEN EINSTELLUNGEN ---
// ==========================================
minSize = 40;
maxSize = 200;
minCirc = 0.40;
maxCirc = 0.90;
blurSigma = 2;
threshMethodMaster = "Otsu";       // Für C1+C2 Maske (Zellerkennung)
deadThreshold = 5;                 // gemessene C3/PI-Rohintensität > 5 = tote Zelle

// ==========================================
// --- AB HIER NICHTS MEHR ÄNDERN ---
// ==========================================

mainDir = getDirectory("Wähle den HAUPT-ORDNER aus (z.B. 'batch 1')");

setBatchMode(true);
print("\\Clear");
print("Starte ALL-CELLS BATCH (misst C1+C2+C3 fuer ALLE Zellen, tot UND lebend)...");

// Globale Zusammenfassung initialisieren
summaryFilePath = mainDir + "Dead_Cell_Summary_AllCells.csv";
File.saveString("Ordner,Zellen Gesamt,Lebende Zellen,Tote Zellen,Tote Zellen (%)\n", summaryFilePath);

processFolder(mainDir);

print("-------------------------------------------------");
print("Fertig! Alle Messungen (lebend + tot) wurden gespeichert.");
print("Globale Zusammenfassung: " + summaryFilePath);
setBatchMode(false);
showMessage("Fertig!", "ALL-CELLS Batch abgeschlossen.\nDetails im Log-Fenster.");


// ------------------------------------------
// FUNKTION: Rekursive Suche nach Ordnern
// ------------------------------------------
function processFolder(folder) {
    list = getFileList(folder);
    hasImages = false;
    for (i = 0; i < list.length; i++) {
        if (endsWith(list[i], ".tif") || endsWith(list[i], ".TIF")) {
            hasImages = true; break;
        }
    }
    if (hasImages) {
        analyzeFolder(folder);
    } else {
        for (i = 0; i < list.length; i++) {
            if (endsWith(list[i], "/")) {
                processFolder(folder + list[i]);
            }
        }
    }
}


// ------------------------------------------
// FUNKTION: Analyse und Messung pro Ordner
// ------------------------------------------
function analyzeFolder(inputDir) {
    run("Clear Results");
    roiManager("reset");
    run("Set Measurements...", "area mean integrated shape display redirect=None decimal=3");

    list = getFileList(inputDir);

    folderTotal  = 0;
    folderLiving = 0;
    folderDead   = 0;

    // CSV-Ausgabedatei für diesen Ordner vorbereiten
    dirNoSlash = substring(inputDir, 0, lengthOf(inputDir)-1);
    lastSlashIndex = lastIndexOf(dirNoSlash, "/");
    if (lastSlashIndex == -1) { lastSlashIndex = lastIndexOf(dirNoSlash, "\\"); }
    folderName = substring(dirNoSlash, lastSlashIndex + 1);

    allCellsCSV = inputDir + folderName + "_AllCells.csv";
    File.saveString("Cell_ID,Area,C1_Mean,C2_Mean,C3_PI_Mean,Ratio_C1_C2,Status\n", allCellsCSV);

    cellCounter = 0;

    for (i = 0; i < list.length; i++) {
        if (startsWith(list[i], "C1") && (endsWith(list[i], ".tif") || endsWith(list[i], ".TIF"))) {

            c1File = list[i];
            c2File = replace(c1File, "C1", "C2");
            c3File = replace(c1File, "C1", "C3");

            if (File.exists(inputDir + c2File) && File.exists(inputDir + c3File)) {

                open(inputDir + c1File); ch1Title = getTitle();
                open(inputDir + c2File); ch2Title = getTitle();
                open(inputDir + c3File); ch3Title = getTitle();

                // 1. Master-Maske (C1+C2) für Zellerkennung
                imageCalculator("Add create", ch1Title, ch2Title);
                masterTitle = getTitle();
                selectWindow(masterTitle);
                run("Gaussian Blur...", "sigma=" + blurSigma);
                setAutoThreshold(threshMethodMaster + " dark");
                setOption("BlackBackground", true);
                run("Convert to Mask");

                // 2. ALLE Zellen finden und als ROIs speichern
                roiManager("reset");
                selectWindow(masterTitle);
                run("Analyze Particles...", "size=" + minSize + "-" + maxSize + " pixel circularity=" + minCirc + "-" + maxCirc + " exclude add");

                totalInImage = roiManager("count");
                folderTotal = folderTotal + totalInImage;

                // 3. Für JEDE Zelle (lebend UND tot): C1, C2, C3 messen
                for (r = 0; r < totalInImage; r++) {
                    roiManager("select", r);

                    // Fläche messen
                    selectWindow(masterTitle);
                    roiManager("select", r);
                    cellArea = getValue("Area");

                    // C1 Intensität messen
                    selectWindow(ch1Title);
                    roiManager("select", r);
                    c1Mean = getValue("Mean");

                    // C2 Intensität messen
                    selectWindow(ch2Title);
                    roiManager("select", r);
                    c2Mean = getValue("Mean");

                    // C3/PI Intensität (Rohdaten, nicht binarisiert)
                    selectWindow(ch3Title);
                    roiManager("select", r);
                    c3Mean = getValue("Mean");

                    // Status direkt aus der gemessenen PI-Rohintensität
                    if (c3Mean > deadThreshold) {
                        cellStatus = "dead";
                        folderDead++;
                    } else {
                        cellStatus = "living";
                        folderLiving++;
                    }

                    // Ratio berechnen (C1/C2, Division durch Null verhindern)
                    if (c2Mean > 0) {
                        ratio = c1Mean / c2Mean;
                    } else {
                        ratio = 0;
                    }

                    cellCounter++;
                    cellID = folderName + "_" + IJ.pad(cellCounter, 5);

                    // Zeile in die Ordner-CSV schreiben
                    line = cellID + "," + d2s(cellArea, 3) + "," + d2s(c1Mean, 3) + "," + d2s(c2Mean, 3) + "," + d2s(c3Mean, 3) + "," + d2s(ratio, 6) + "," + cellStatus + "\n";
                    File.append(line, allCellsCSV);
                }

                // Aufräumen
                selectWindow(masterTitle); close();
                selectWindow(ch1Title); close();
                selectWindow(ch2Title); close();
                selectWindow(ch3Title); close();
            }
        }
    }

    // 4. ZÄHLUNG an globale Summary anhängen
    if (folderTotal > 0) {
        deadPercent = (folderDead / folderTotal) * 100;
        line = folderName + "," + folderTotal + "," + folderLiving + "," + folderDead + "," + d2s(deadPercent, 4) + "\n";
        File.append(line, summaryFilePath);
        print("-> " + folderName + ": " + folderTotal + " Zellen total (" + folderDead + " tot = " + d2s(deadPercent, 1) + "%) -> " + folderName + "_AllCells.csv");
    }
}
