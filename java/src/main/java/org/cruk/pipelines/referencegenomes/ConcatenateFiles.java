package org.cruk.pipelines.referencegenomes;

import static org.apache.commons.lang3.StringUtils.EMPTY;
import static org.apache.commons.lang3.StringUtils.isNotEmpty;
import static org.apache.commons.lang3.StringUtils.leftPad;
import static org.apache.commons.lang3.StringUtils.upperCase;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.math.BigInteger;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.List;
import java.util.concurrent.Callable;

import org.apache.commons.compress.compressors.CompressorStreamFactory;
import org.apache.commons.io.IOUtils;
import org.cruk.common.compression.CompressionOutputStreamBuilder;
import org.cruk.common.compression.CompressionUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.ExitCode;
import picocli.CommandLine.Option;
import picocli.CommandLine.Parameters;

@Command(name = "RecreateFasta",
         descriptionHeading = "Disassemble a FASTA reference file and recreated it with specific chromosomes or contigs in order.",
         mixinStandardHelpOptions = true,
         description = {
                 "Supported compression methods are: ",
                 CompressorStreamFactory.GZIP,
                 CompressorStreamFactory.BZIP2,
                 CompressorStreamFactory.XZ,
                 CompressorStreamFactory.PACK200,
                 CompressorStreamFactory.DEFLATE,
                 EMPTY,
                 "Compression level must be in the range 0-9 inclusive."})
public class ConcatenateFiles implements Callable<Integer>
{
    private static final Logger logger = LoggerFactory.getLogger(ConcatenateFiles.class);

    @Option(names = { "-z", "--gzip" }, description = "Zip output as it a written (same as \"-j gz\").")
    boolean zip;

    @Option(names = { "-c", "--checksum" }, paramLabel = "file",
            description = "Checksum file for the output.")
    File checksumFile;

    @Option(names = { "-o", "--output" }, paramLabel = "file",
            description = "File to write the output to.")
    File outputFile;

    @Option(names = { "-s", "--suffix" }, paramLabel = "text",
            description = "A suffix to trim off the output file name as it is printed in the checksum file.")
    String suffix;

    @Option(names = { "-a", "--algorithm" }, paramLabel = "name", defaultValue = "MD5",
            description =  "The checksum algorithm to use. Default is MD5.")
    String algorithm;

    @Option(names = { "-j", "--compression" }, paramLabel = "algorithm",
            description = "The type of compression to use on the output.")
    String compression;

    @Option(names = { "-l", "--level" }, paramLabel = "0-9", defaultValue = "1",
            description = "Compression level to use for those types that support it.")
    int compressionLevel = 1;

    @Parameters
    List<File> inputFiles;

    public ConcatenateFiles()
    {
    }

    @Override
    public Integer call() throws Exception
    {
        MessageDigest digest = null;

        if (zip)
        {
            compression = CompressorStreamFactory.GZIP;
        }

        algorithm = upperCase(algorithm);

        final int largeBufferSize = 4 * 1024 * 1024;

        OutputStream out = null;
        try
        {
            if (checksumFile != null)
            {
                digest = MessageDigest.getInstance(algorithm);
            }

            out = outputFile != null ? new FileOutputStream(outputFile) : System.out;

            out = CompressionOutputStreamBuilder.newInstance()
                    .withBufferSize(largeBufferSize)
                    .withCompressionMethod(compression)
                    .withCompressionLevel(compressionLevel)
                    .addCompressionStream(out, digest);

            for (File f : inputFiles)
            {
                try (InputStream in = CompressionUtils.openInputStream(f, largeBufferSize))
                {
                    IOUtils.copyLarge(in, out);
                }
                catch (FileNotFoundException e)
                {
                    // Just skip.
                    logger.error("Cannot open file {}", e.getMessage());
                }
            }

            out.flush();
            if (outputFile != null)
            {
                out.close();
            }

            if (checksumFile != null)
            {
                try
                {
                    PrintWriter checksumWriter = new PrintWriter(checksumFile);

                    BigInteger checksum = new BigInteger(1, digest.digest());
                    checksumWriter.print(leftPad(checksum.toString(16), 32, '0'));
                    if (outputFile != null)
                    {
                        String name = outputFile.getName();
                        if (isNotEmpty(suffix) && name.endsWith(suffix))
                        {
                            name = name.substring(0, name.length() - suffix.length());
                        }

                        checksumWriter.print("  ");
                        checksumWriter.println(name);
                    }

                    checksumWriter.close();
                }
                catch (IOException e)
                {
                    logger.error("Cannot write checksum file: {}", e.getMessage());
                }
            }
        }
        catch (NoSuchAlgorithmException e)
        {
            logger.error("'{}' is not a supported checksum algorithm.", algorithm);
            logger.error("See https://docs.oracle.com/en/java/javase/17/docs/specs/security/standard-names.html#messagedigest-algorithms" +
                         " for the list of standard algorithms.");
            return ExitCode.SOFTWARE;
        }
        finally
        {
            if (out != null && outputFile != null)
            {
                out.close();
            }
        }

        return ExitCode.OK;
    }

    public static void main(String[] args)
    {
        int returnCode = ExitCode.SOFTWARE;
        try
        {
            returnCode = new CommandLine(new ConcatenateFiles()).execute(args);
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
