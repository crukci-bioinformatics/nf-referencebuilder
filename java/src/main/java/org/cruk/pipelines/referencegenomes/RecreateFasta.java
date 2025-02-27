package org.cruk.pipelines.referencegenomes;

import static java.nio.charset.StandardCharsets.US_ASCII;
import static org.apache.commons.lang3.StringUtils.EMPTY;
import static org.apache.commons.lang3.StringUtils.isNotBlank;
import static org.apache.commons.lang3.StringUtils.join;
import static org.apache.commons.lang3.StringUtils.trimToNull;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.io.Reader;
import java.io.Writer;
import java.text.NumberFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import java.util.stream.Stream;

import org.apache.commons.compress.archivers.tar.TarArchiveEntry;
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream;
import org.apache.commons.io.FileUtils;
import org.apache.commons.io.IOUtils;
import org.cruk.common.comparators.numericname.NumericalFilenameComparator;
import org.cruk.common.compression.CompressionUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.ExitCode;
import picocli.CommandLine.Option;

@Command(name = "RecreateFasta",
         descriptionHeading = "Disassemble a FASTA reference file and recreated it with specific chromosomes or contigs in order.",
         mixinStandardHelpOptions = true,
         description = {
             EMPTY,
             "The input file can be FASTA, compressed or not, or TAR files containing individual",
             "FASTA files. Ensembl sources tend to be the format, UCSC the latter.",
             EMPTY,
             "The sort order must be a list of space or comma separated contig identifiers.",
             "Those contigs will appear in the resulting FASTA first and in the order given.",
             "Any other contigs will be added to the end in alpha-numerical order."
        })
public class RecreateFasta implements Callable<Integer>
{
    static final Pattern HEADER_LINE = Pattern.compile("^>([\\.\\w]+).*$");

    static final NumberFormat HUNDRED_FORMAT = NumberFormat.getIntegerInstance();
    static
    {
        HUNDRED_FORMAT.setGroupingUsed(false);
        HUNDRED_FORMAT.setMinimumIntegerDigits(3);
    }

    private static final int smallBufferSize = 32 * 1024;
    private static final int largeBufferSize = 1024 * 1024;

    private static final Logger logger = LoggerFactory.getLogger(RecreateFasta.class);

    private byte[] copyBuffer;

    @Option(names = { "-i", "--input" }, required = true, paramLabel = "file",
            description = "The reference FASTA as downloaded.")
    File inputFile;

    @Option(names = { "-o", "--output" }, required = true, paramLabel = "file",
            description = "File to write the output to.")
    File outputFile;

    @Option(names = { "-t", "--temp-dir" }, required = true, paramLabel = "directory",
            description = "The temporary directory to work with.")
    File tempDir;

    @Option(names = { "-a", "--assembly" }, required = true, paramLabel = "name",
            description =  "The name of the assembly.")
    String assembly;

    File workingDir;

    @Option(names = { "-c", "--contig-order" }, required = true, paramLabel = "list",
            description = "The order of chromosomes and key contigs in the output file.")
    String contigOrderString;

    @Option(names = { "-k", "--keep" }, description = "Keep intermediate files after execution.")
    boolean keepIntermediates = false;

    List<String> contigOrder = Collections.emptyList();
    List<String> readContigs = new ArrayList<>(100);
    Map<String, File> readContigFiles = new HashMap<>();

    private Map<Integer, File> innerTempDirs = new HashMap<>();


    public RecreateFasta()
    {
    }

    private byte[] getBuffer()
    {
        if (copyBuffer == null)
        {
            copyBuffer = new byte[largeBufferSize];
        }
        return copyBuffer;
    }

    void expandSource() throws IOException
    {
        workingDir = new File(tempDir, assembly);

        if (!workingDir.isDirectory())
        {
            FileUtils.forceMkdir(workingDir);
        }

        readContigs.clear();
        readContigFiles.clear();
        innerTempDirs.clear();

        // Need the extra buffer to use mark().

        try (InputStream bottomStream = new BufferedInputStream(CompressionUtils.openInputStream(inputFile, smallBufferSize), smallBufferSize * 2))
        {
            if (!bottomStream.markSupported())
            {
                throw new IOException("Cannot use mark() from a " + bottomStream.getClass().getName());
            }

            bottomStream.mark(256);

            Reader reader = new InputStreamReader(bottomStream, US_ASCII);

            // Raw FASTA starts with a >
            boolean tar = reader.read() != '>';

            bottomStream.reset();

            if (tar)
            {
                // Hope this is a TAR file.
                expandTar(bottomStream);
            }
            else
            {
                // This is regular FASTA.
                expandAndSplitFasta(bottomStream);
            }
        }

        if (logger.isInfoEnabled() && readContigs.size() < 100)
        {
            logger.info("Found these chromosomes/contigs: {}", join(readContigs, " "));
        }
        else
        {
            logger.info("Found {} chromosomes/contigs", readContigs.size());
        }
    }

    private void expandAndSplitFasta(InputStream inStream) throws IOException
    {
        logger.debug("Treating {} as a single FASTA file.", inputFile.getName());

        Writer outStream = null;
        int contigCount = 0;

        try (BufferedReader reader = new BufferedReader(new InputStreamReader(inStream, US_ASCII), smallBufferSize))
        {
            String line;
            while ((line = reader.readLine()) != null)
            {
                if (line.charAt(0) == '>')
                {
                    ++contigCount;

                    // Have a header line. Use the name as the file name.
                    Matcher m = HEADER_LINE.matcher(line);
                    if (!m.matches())
                    {
                        throw new AssertionError("FASTA header line doesn't match pattern.");
                    }

                    String contigName = m.group(1);

                    if (outStream != null)
                    {
                        outStream.close();
                    }

                    File outFile = new File(getInnerTemp(contigCount), contigName + ".fa");

                    outStream = new OutputStreamWriter(new BufferedOutputStream(new FileOutputStream(outFile), smallBufferSize), US_ASCII);

                    logger.info("Extracting {}", outFile.getName());

                    readContigs.add(contigName);
                    readContigFiles.put(contigName, outFile);
                }

                if (outStream == null)
                {
                    throw new IOException(inputFile.getName() + " does not start with an FASTA header line.");
                }

                outStream.write(line);
                outStream.write('\n'); // FASTA expects Unix line ends.
            }
        }
        finally
        {
            if (outStream != null)
            {
                outStream.close();
            }
        }

        logger.info("FASTA extraction complete.");
    }

    private void expandTar(InputStream inStream) throws IOException
    {
        logger.debug("Treating {} as a TAR archive.", inputFile.getName());

        int contigCount = 0;

        TarArchiveInputStream tarStream = new TarArchiveInputStream(inStream);
        TarArchiveEntry entry;
        while ((entry = tarStream.getNextTarEntry()) != null)
        {
            if (entry.isFile())
            {
                ++contigCount;

                logger.info("Extracting {}", entry.getName());

                File fastaFile = new File(getInnerTemp(contigCount), entry.getName());

                try (OutputStream outStream = new FileOutputStream(fastaFile))
                {
                    IOUtils.copyLarge(tarStream, outStream, getBuffer());
                }

                try (BufferedReader reader = new BufferedReader(new FileReader(fastaFile), smallBufferSize))
                {
                    String header = reader.readLine();

                    // Have a header line. Use the name as the file name.
                    Matcher m = HEADER_LINE.matcher(header);
                    if (!m.matches())
                    {
                        throw new AssertionError("FASTA header line doesn't match pattern.");
                    }

                    String contigName = m.group(1);

                    readContigs.add(contigName);
                    readContigFiles.put(contigName, fastaFile);
                }
            }
        }

        logger.info("TAR extraction complete.");
    }

    /**
     * One particular reference, xla.XL9.2, contains 100,000+ scaffolds.
     * This produces a problem with the number of files in a directory. This
     * method gets or creates a directory for up to 1000 contigs in each directory
     * numbered for the hundred thousand files.
     *
     * @param contigCount The current count for the number of contigs found.
     *
     * @return The directory to write the current contig file into.
     *
     * @throws IOException if creating the directory fails.
     */
    private File getInnerTemp(int contigCount) throws IOException
    {
        Integer section = contigCount / 1000;

        File dir = innerTempDirs.get(section);
        if (dir == null)
        {
            dir = new File(workingDir, HUNDRED_FORMAT.format(section));
            if (!dir.isDirectory())
            {
                FileUtils.forceMkdir(dir);
            }
        }

        return dir;
    }

    void writeFasta() throws Exception
    {
        if (readContigFiles.isEmpty())
        {
            logger.warn("No contig files to create from. Has everything run ok?");
            return;
        }

        Collections.sort(readContigs, NumericalFilenameComparator.INSTANCE);

        try (OutputStream out = new FileOutputStream(outputFile))
        {
            // Write requested contigs in the order given.

            writeContig(contigOrder, out);

            // Write out remaining contigs in alphanumeric order.

            writeContig(readContigs, out);
        }
        catch (Throwable e)
        {
            outputFile.delete();
            throw e;
        }
    }

    private void writeContig(List<String> contigNames, OutputStream out)
    throws IOException
    {
        for (String name : contigNames)
        {
            // Removing from the map makes sure it is not processed more than once.

            File contigFile = readContigFiles.remove(name);

            if (contigFile != null)
            {
                logger.info("Writing contig {}", name);

                try (InputStream in = new FileInputStream(contigFile))
                {
                    IOUtils.copyLarge(in, out, getBuffer());
                }
            }
        }
    }


    @Override
    public Integer call() throws Exception
    {
        if (tempDir == null)
        {
            tempDir = new File(System.getProperty("java.io.tmpdir"));
        }

        if (isNotBlank(contigOrderString))
        {
            contigOrder = Stream.of(contigOrderString.split("[^\\.\\w]+"))
                    .map(c -> trimToNull(c))
                    .filter(c -> c != null)
                    .collect(Collectors.toList());
        }

        expandSource();

        writeFasta();

        if (!keepIntermediates)
        {
            FileUtils.deleteQuietly(workingDir);
        }

        return 0;
    }

    public static void main(String[] args)
    {
        int returnCode = ExitCode.SOFTWARE;
        try
        {
            returnCode = new CommandLine(new RecreateFasta()).execute(args);
        }
        catch (OutOfMemoryError e)
        {
            returnCode = 104;
            e.printStackTrace();
        }
        catch (Throwable e)
        {
            e.printStackTrace();
        }
        finally
        {
            System.exit(returnCode);
        }
    }
}
